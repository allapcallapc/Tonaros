import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonaros/app_scope.dart';
import 'package:tonaros/main.dart';
import 'package:tonaros/services/cues.dart';
import 'package:tonaros/services/session_store.dart';
import 'package:tonaros/services/settings_store.dart';
import 'package:tonaros/services/update_controller.dart';
import 'package:tonaros/services/update_service.dart';

class FakeUpdateService extends UpdateService {
  FakeUpdateService(this.result, {this.pending});

  final UpdateInfo? result;

  /// When set, checkForUpdate() doesn't resolve until this completes.
  final Completer<void>? pending;
  int checks = 0;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    checks++;
    await pending?.future;
    return result;
  }
}

/// Pumps the whole app on fresh in-memory storage.
Future<SessionStore> pumpApp(
  WidgetTester tester, {
  UpdateService? updateService,
  Map<String, Object> prefs = const {},
}) async {
  PackageInfo.setMockInitialValues(
    appName: 'Tonaros',
    packageName: 'com.tonaros.app',
    version: '1.2.3',
    buildNumber: '1',
    buildSignature: '',
  );
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final sessions = SessionStore(sharedPrefs);
  await tester.pumpWidget(TonarosApp(
    sessions: sessions,
    settings: SettingsStore(sharedPrefs),
    updates: UpdateController(updateService ?? FakeUpdateService(null)),
  ));
  await tester.pumpAndSettle();
  return sessions;
}

/// Records cues instead of playing them.
class FakeCueOutput implements CueOutput {
  final played = <Cue>[];
  final vibrated = <Cue>[];
  bool? keepAwake;

  @override
  Future<void> play(Cue cue) async => played.add(cue);

  @override
  Future<void> vibrate(Cue cue) async => vibrated.add(cue);

  @override
  Future<void> setKeepAwake(bool on) async => keepAwake = on;

  @override
  Future<void> dispose() async {}
}

/// [child] under an [AppScope] on fresh in-memory storage.
Future<Widget> withAppScope(Widget child,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  return AppScope(
    sessions: SessionStore(sharedPrefs),
    settings: SettingsStore(sharedPrefs),
    updates: UpdateController(FakeUpdateService(null)),
    child: child,
  );
}
