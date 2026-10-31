import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'config/app_config.dart';
import 'screens/sessions_screen.dart';
import 'services/cues.dart';
import 'services/history_store.dart';
import 'services/session_store.dart';
import 'services/settings_store.dart';
import 'services/update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(TonarosApp(
    sessions: SessionStore(prefs),
    history: HistoryStore(prefs),
    settings: SettingsStore(prefs),
    updates: UpdateController(),
    // Preloads the cue sounds at launch, ready for the first session.
    cues: DeviceCueOutput(),
  ));
}

/// The logo's mid-gradient purple, between its pink and teal ends.
const brandColor = Color(0xFF5E5BC9);

ThemeData buildTheme(Brightness brightness) {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: brandColor,
      brightness: brightness,
    ),
    useMaterial3: true,
  );
  // Large, easy-to-hit buttons throughout: the app is used mid-exercise.
  const minSize = WidgetStatePropertyAll(Size(64, 52));
  return base.copyWith(
    // Keeps app bar actions clear of the non-prod corner banner.
    appBarTheme: AppBarTheme(
      actionsPadding: EdgeInsets.only(right: AppConfig.isProd ? 0 : 32),
    ),
    filledButtonTheme:
        const FilledButtonThemeData(style: ButtonStyle(minimumSize: minSize)),
    outlinedButtonTheme:
        const OutlinedButtonThemeData(style: ButtonStyle(minimumSize: minSize)),
  );
}

class TonarosApp extends StatelessWidget {
  const TonarosApp({
    super.key,
    required this.sessions,
    required this.history,
    required this.settings,
    required this.updates,
    required this.cues,
  });

  final SessionStore sessions;
  final HistoryStore history;
  final SettingsStore settings;
  final UpdateController updates;
  final CueOutput cues;

  @override
  Widget build(BuildContext context) {
    final app = AppScope(
      sessions: sessions,
      history: history,
      settings: settings,
      updates: updates,
      cues: cues,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'Tonaros',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          home: const SessionsScreen(),
        ),
      ),
    );
    if (AppConfig.isProd) return app;
    // Makes a staging/local build impossible to mistake for production.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        message: AppConfig.environment.toUpperCase(),
        location: BannerLocation.topEnd,
        color: Colors.orange.shade800,
        child: app,
      ),
    );
  }
}
