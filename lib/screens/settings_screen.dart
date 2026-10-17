import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_scope.dart';
import '../config/app_config.dart';
import '../services/update_service.dart';

/// Theme, "Check for updates" (Android), About and the app version.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  /// Flutter's stock About dialog, which also links to the generated
  /// open-source licenses page for every bundled package.
  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Tonaros',
      applicationVersion: _version,
      applicationIcon: Image.asset('assets/logo.png', width: 48, height: 48),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final updates = scope.updates;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, updates]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              title: const Text('Theme'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.setThemeMode(s.first),
                ),
              ),
            ),
            const Divider(),
            if (UpdateService.isSupported)
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('Check for updates'),
                subtitle: updates.statusMessage == null
                    ? null
                    : Text(updates.statusMessage!),
                trailing: updates.checking
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : null,
                enabled: !updates.checking,
                onTap: () => updates.checkNow(context),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: _showAbout,
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                [
                  'Tonaros',
                  if (_version != null) 'v$_version',
                  if (!AppConfig.isProd) AppConfig.environment,
                ].join(' · '),
                style: textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
