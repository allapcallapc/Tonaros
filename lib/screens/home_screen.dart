import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

/// Placeholder landing screen: logo, app name, version and environment,
/// plus a manual "Check for updates" on Android.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.updateService});

  /// Injectable for tests; defaults to a real [UpdateService].
  final UpdateService? updateService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final UpdateService _updateService =
      widget.updateService ?? UpdateService();
  String? _version;
  bool _checkingForUpdate = false;
  String? _updateStatusMessage;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
    // Check once on launch so a sideloaded APK still gets notified of new
    // releases - see UpdateService.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnLaunch());
  }

  Future<void> _checkOnLaunch() async {
    if (!UpdateService.isSupported) return;
    final update = await _updateService.checkForUpdate();
    if (update == null || !mounted) return;
    await showUpdateAvailableDialog(context, _updateService, update);
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingForUpdate = true;
      _updateStatusMessage = 'Checking for updates…';
    });
    final update = await _updateService.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checkingForUpdate = false;
      _updateStatusMessage = update == null ? "You're up to date." : null;
    });
    if (update != null) {
      await showUpdateAvailableDialog(context, _updateService, update);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', width: 160, height: 160),
                const SizedBox(height: 24),
                Text('Tonaros', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  [
                    if (_version != null) 'v$_version',
                    if (!AppConfig.isProd) AppConfig.environment,
                  ].join(' · '),
                  style: textTheme.bodyMedium,
                ),
                if (UpdateService.isSupported) ...[
                  const SizedBox(height: 24),
                  _checkingForUpdate
                      ? const CircularProgressIndicator()
                      : OutlinedButton(
                          onPressed: _checkForUpdates,
                          child: const Text('Check for updates'),
                        ),
                  if (_updateStatusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_updateStatusMessage!, style: textTheme.bodySmall),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
