import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/services/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    // checkForUpdate() is a no-op off Android (see UpdateService.isSupported)
    // - the test host platform otherwise defaults to whatever's running the
    // test runner, not Android.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Tonaros',
      packageName: 'com.tonaros.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Map<String, dynamic> releaseJson({
    String tag = 'v1.1.0',
    List<Map<String, dynamic>>? assets,
  }) => {
    'tag_name': tag,
    'assets': assets ??
        [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/allapcallapc/Tonaros/releases/download/$tag/app-release.apk',
          },
        ],
  };

  UpdateService serviceFor(http.Client client) => UpdateService(httpClient: client);

  test('returns UpdateInfo when a newer release exists', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.github.com/repos/allapcallapc/Tonaros/releases/latest');
      return http.Response(jsonEncode(releaseJson()), 200);
    });

    final update = await serviceFor(client).checkForUpdate();

    expect(update, isNotNull);
    expect(update!.version, '1.1.0');
    expect(update.downloadUrl, contains('app-release.apk'));
  });

  test('returns null when already on the latest version', () async {
    final client = MockClient((request) async => http.Response(jsonEncode(releaseJson(tag: 'v1.0.0')), 200));

    final update = await serviceFor(client).checkForUpdate();

    expect(update, isNull);
  });

  test('returns null when the latest release is older (no downgrade prompts)', () async {
    final client = MockClient((request) async => http.Response(jsonEncode(releaseJson(tag: 'v0.9.0')), 200));

    final update = await serviceFor(client).checkForUpdate();

    expect(update, isNull);
  });

  test('returns null when the release has no APK asset', () async {
    final client = MockClient((request) async => http.Response(jsonEncode(releaseJson(assets: [])), 200));

    final update = await serviceFor(client).checkForUpdate();

    expect(update, isNull);
  });

  test('returns null on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('not found', 404));

    final update = await serviceFor(client).checkForUpdate();

    expect(update, isNull);
  });

  test('returns null on a network error', () async {
    final client = MockClient((request) async => throw Exception('network down'));

    final update = await serviceFor(client).checkForUpdate();

    expect(update, isNull);
  });

  test('strips a leading "v" from the tag name', () async {
    final client = MockClient((request) async => http.Response(jsonEncode(releaseJson(tag: 'v2.0.0')), 200));

    final update = await serviceFor(client).checkForUpdate();

    expect(update!.version, '2.0.0');
  });

  group('downloadAndInstall', () {
    late Directory tempDir;
    late List<MethodCall> installCalls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = Directory.systemTemp.createTempSync('tonaros_update_test');
      installCalls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.tonaros/updates'),
        (call) async {
          installCalls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('com.tonaros/updates'), null);
      tempDir.deleteSync(recursive: true);
    });

    const update = UpdateInfo(
      version: '1.1.0',
      downloadUrl: 'https://example.com/app-release.apk',
    );

    test('hands the downloaded APK to the installer', () async {
      final client = MockClient((request) async => http.Response('apk-bytes', 200));

      await serviceFor(client).downloadAndInstall(update);

      expect(installCalls, hasLength(1));
      final path = (installCalls.single.arguments as Map)['filePath'] as String;
      expect(File(path).readAsStringSync(), 'apk-bytes');
    });

    test('throws and does not install on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('Not Found', 404));

      await expectLater(
        serviceFor(client).downloadAndInstall(update),
        throwsA(isA<HttpException>()),
      );
      expect(installCalls, isEmpty);
    });

    /// A response that sends one chunk and then stalls forever.
    MockClient stallingClient() => MockClient.streaming((request, body) async {
          final controller = StreamController<List<int>>();
          controller.add(utf8.encode('partial'));
          return http.StreamedResponse(controller.stream, 200, contentLength: 100);
        });

    test('times out when the download stalls, leaving no partial APK', () async {
      final service = UpdateService(
        httpClient: stallingClient(),
        downloadStallTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        service.downloadAndInstall(update),
        throwsA(isA<TimeoutException>()),
      );
      expect(installCalls, isEmpty);
      expect(File('${tempDir.path}/apk_updates/tonaros-update.apk').existsSync(), isFalse);
    });

    test('times out when the server never responds', () async {
      final service = UpdateService(
        httpClient: MockClient.streaming((request, body) => Completer<http.StreamedResponse>().future),
        downloadStallTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        service.downloadAndInstall(update),
        throwsA(isA<TimeoutException>()),
      );
      expect(installCalls, isEmpty);
    });

    test('stops with UpdateCancelledException when cancelled', () async {
      final cancel = Completer<void>();
      final progress = <double>[];
      final download = serviceFor(stallingClient()).downloadAndInstall(
        update,
        cancel: cancel.future,
        onProgress: progress.add,
      );

      // Cancel once the first chunk has arrived.
      while (progress.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      cancel.complete();

      await expectLater(download, throwsA(isA<UpdateCancelledException>()));
      expect(installCalls, isEmpty);
    });
  });
}
