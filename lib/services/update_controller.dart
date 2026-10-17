import 'package:flutter/material.dart';

import '../widgets/update_dialog.dart';
import 'update_service.dart';

/// Runs update checks for the whole app, so the launch-time check (from the
/// sessions screen) and a manual one (from settings) can't overlap: two
/// stacked dialogs, two downloads writing the same APK file.
class UpdateController extends ChangeNotifier {
  UpdateController([UpdateService? service])
      : service = service ?? UpdateService();

  final UpdateService service;

  bool get checking => _checking;
  bool _checking = false;

  /// Result of the last manual check, shown under its button.
  String? get statusMessage => _statusMessage;
  String? _statusMessage;

  /// True from the start of a check until its update dialog/download flow
  /// finishes.
  bool _flowActive = false;

  /// Silent unless an update is available - see UpdateService.
  Future<void> checkOnLaunch(BuildContext context) async {
    if (!UpdateService.isSupported) return;
    await _run(context, reportResult: false);
  }

  Future<void> checkNow(BuildContext context) =>
      _run(context, reportResult: true);

  Future<void> _run(BuildContext context, {required bool reportResult}) async {
    if (_flowActive) return;
    _flowActive = true;
    try {
      _checking = true;
      _statusMessage = reportResult ? 'Checking for updates…' : null;
      notifyListeners();
      final update = await service.checkForUpdate();
      _checking = false;
      _statusMessage =
          reportResult && update == null ? "You're up to date." : null;
      notifyListeners();
      if (update != null && context.mounted) {
        await showUpdateAvailableDialog(context, service, update);
      }
    } finally {
      _checking = false;
      _flowActive = false;
    }
  }
}
