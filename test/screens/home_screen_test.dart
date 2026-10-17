import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tonaros/screens/home_screen.dart';
import 'package:tonaros/services/update_service.dart';

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.result);

  final UpdateInfo? result;
  int checks = 0;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    checks++;
    return result;
  }
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Tonaros',
      packageName: 'com.tonaros.app',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('shows the app name, version and environment', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(updateService: _FakeUpdateService(null)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tonaros'), findsOneWidget);
    // No --dart-define-from-file in tests, so AppConfig reports "local".
    expect(find.text('v1.2.3 · local'), findsOneWidget);
  });

  testWidgets('hides "Check for updates" off Android', (tester) async {
    // flutter_test defaults to Android, so pick a non-Android platform.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(updateService: _FakeUpdateService(null)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Check for updates'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Android, checks on launch and on demand', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = _FakeUpdateService(null);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(updateService: service)));
    await tester.pumpAndSettle();
    expect(service.checks, 1);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(service.checks, 2);
    expect(find.text("You're up to date."), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Android, prompts when an update is available', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = _FakeUpdateService(
      const UpdateInfo(version: '2.0.0', downloadUrl: 'https://example.com/a.apk'),
    );
    await tester.pumpWidget(MaterialApp(home: HomeScreen(updateService: service)));
    await tester.pumpAndSettle();

    expect(find.text('Version 2.0.0 is available. Update now?'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
