import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const TonarosApp());
}

/// The logo's mid-gradient purple, between its pink and teal ends.
const brandColor = Color(0xFF5E5BC9);

class TonarosApp extends StatelessWidget {
  const TonarosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'Tonaros',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brandColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
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
