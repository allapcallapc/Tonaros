import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonaros/app_scope.dart';
import 'package:tonaros/main.dart';
import 'package:tonaros/models/history_entry.dart';
import 'package:tonaros/services/background_session.dart';
import 'package:tonaros/services/cues.dart';
import 'package:tonaros/services/history_store.dart';
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
    history: HistoryStore(sharedPrefs),
    settings: SettingsStore(sharedPrefs),
    updates: UpdateController(updateService ?? FakeUpdateService(null)),
    cues: FakeCueOutput(),
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
  final ValueNotifier<bool> vibrationAvailable = ValueNotifier(true);

  @override
  Future<void> play(Cue cue) async => played.add(cue);

  @override
  Future<void> vibrate(Cue cue) async => vibrated.add(cue);

  @override
  Future<void> setKeepAwake(bool on) async => keepAwake = on;
}

/// [child] under an [AppScope] on fresh in-memory storage.
Future<Widget> withAppScope(Widget child,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  return AppScope(
    sessions: SessionStore(sharedPrefs),
    history: HistoryStore(sharedPrefs),
    settings: SettingsStore(sharedPrefs),
    updates: UpdateController(FakeUpdateService(null)),
    cues: FakeCueOutput(),
    backgroundSession: FakeBackgroundSession.new,
    child: child,
  );
}

/// A run of session [sessionId] that ended at [at].
HistoryEntry run(DateTime at,
        {bool completed = true, String sessionId = 's'}) =>
    HistoryEntry(
      id: '$sessionId${at.millisecondsSinceEpoch}',
      sessionId: sessionId,
      sessionName: 'S',
      endedAt: at,
      completed: completed,
      reps: 1,
      holds: 1,
      activeTime: const Duration(seconds: 30),
    );

/// Records what the background notification would show.
class FakeBackgroundSession implements BackgroundSession {
  /// The texts shown, in order.
  final shown = <String>[];
  bool running = false;

  /// The latest status, e.g. for its button label and countdown.
  BackgroundStatus? last;

  /// How many times update() was called.
  int updates = 0;

  /// Taps the notification's button as it is currently labelled.
  void tapAction() => tapLabel(last?.action);

  /// Taps the notification's button showing [label], e.g. one the latest
  /// update hasn't replaced yet.
  void tapLabel(String? label) => _onAction!(label);

  /// Swipes the app away from recents.
  void dismiss() => _onDismissed!();

  ValueChanged<String?>? _onAction;
  VoidCallback? _onDismissed;

  @override
  Future<void> start(
    BackgroundStatus status, {
    required ValueChanged<String?> onAction,
    required VoidCallback onDismissed,
  }) async {
    running = true;
    _onAction = onAction;
    _onDismissed = onDismissed;
    last = status;
    shown.add(status.text);
  }

  @override
  Future<void> update(BackgroundStatus status) async {
    last = status;
    updates++;
    // A countdown resync or a button change keeps the text.
    if (shown.last != status.text) shown.add(status.text);
  }

  /// How many times ensureStarted() was called.
  int ensureStartedCalls = 0;

  @override
  Future<void> ensureStarted(BackgroundStatus status) async =>
      ensureStartedCalls++;

  /// Runs when stop() is called, e.g. to check what was done by then.
  VoidCallback? onStop;

  @override
  Future<void> stop() async {
    running = false;
    onStop?.call();
  }
}
