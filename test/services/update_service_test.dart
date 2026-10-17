import 'dart:convert';

import 'package:flutter/foundation.dart';
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
}
