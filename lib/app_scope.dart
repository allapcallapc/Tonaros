import 'package:flutter/widgets.dart';

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
    required super.child,
  });

  final SessionStore sessions;
  final SettingsStore settings;
  final UpdateController updates;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      sessions != oldWidget.sessions ||
      settings != oldWidget.settings ||
      updates != oldWidget.updates;
}
