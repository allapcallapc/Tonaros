import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/services/update_service.dart';

import '../test_app.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the version and environment', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    // No --dart-define-from-file in tests, so AppConfig reports "local".
    expect(find.text('Tonaros · v1.2.3 · local'), findsOneWidget);
  });

  testWidgets('switches theme', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('hides "Check for updates" off Android', (tester) async {
    // flutter_test defaults to Android, so pick a non-Android platform.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.text('Check for updates'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Android, checks on launch and on demand', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeUpdateService(null);
    await pumpApp(tester, updateService: service);
    expect(service.checks, 1);

    await openSettings(tester);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(service.checks, 2);
    expect(find.text("You're up to date."), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Android, prompts on launch when an update is available',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = FakeUpdateService(
      const UpdateInfo(version: '2.0.0', downloadUrl: 'https://example.com/a.apk'),
    );
    await pumpApp(tester, updateService: service);

    expect(find.text('Version 2.0.0 is available. Update now?'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Android, no manual check while the launch check is running',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final pending = Completer<void>();
    final service = FakeUpdateService(null, pending: pending);
    await pumpApp(tester, updateService: service);
    // pumpApp settles, but the check is still pending.
    expect(service.checks, 1);

    // Not pumpAndSettle: the "checking" spinner never settles.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    expect(service.checks, 1);

    pending.complete();
    await tester.pumpAndSettle();
    // The launch check stays silent when there's nothing to report.
    expect(find.text("You're up to date."), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('About opens a dialog with the version and licenses link',
      (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutDialog), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AboutDialog), matching: find.text('1.2.3')),
      findsOneWidget,
    );
    expect(find.text('View licenses'), findsOneWidget);
  });
}
