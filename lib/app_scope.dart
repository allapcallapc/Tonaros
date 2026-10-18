import 'package:flutter/widgets.dart';

import 'services/cues.dart';
import 'services/session_store.dart';
import 'services/settings_store.dart';
import 'services/update_controller.dart';

/// Hands the app-wide stores down the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.sessions,
    required this.settings,
    required this.updates,
    required this.cues,
    required super.child,
  });

  final SessionStore sessions;
  final SettingsStore settings;
  final UpdateController updates;

  /// Cue sounds/vibration, loaded once for the whole app.
  final CueOutput cues;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!;
  }

  /// Like [of], without subscribing to changes - usable from initState.
  static AppScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      sessions != oldWidget.sessions ||
      settings != oldWidget.settings ||
      updates != oldWidget.updates ||
      cues != oldWidget.cues;
}
