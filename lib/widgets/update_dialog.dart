import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Shows the "update available" prompt and, if the user accepts, walks them
/// through granting the install-unknown-apps permission (if needed) and
/// downloading + installing the update.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  UpdateService updateService,
  UpdateInfo update,
) async {
  final shouldUpdate = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Update available'),
      content: Text('Version ${update.version} is available. Update now?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Update now'),
        ),
      ],
    ),
  );
  if (shouldUpdate != true || !context.mounted) return;

  final permissionGranted = await updateService.isInstallPermissionGranted();
  if (!permissionGranted) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update available'),
        content: const Text(
          'Installing this update requires permission to install unknown '
          'apps. Grant it in Settings, then try "Check for updates" again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              await updateService.openInstallPermissionSettings();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    // Whether or not the permission was granted, there's no reliable signal
    // to resume on once we've handed off to system settings - the user just
    // retries "Check for updates" afterwards.
    return;
  }

  if (!context.mounted) return;
  await _downloadWithProgress(context, updateService, update);
}

Future<void> _downloadWithProgress(
  BuildContext context,
  UpdateService updateService,
  UpdateInfo update,
) async {
  final progress = ValueNotifier<double>(0);

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Downloading update'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, child) => LinearProgressIndicator(
          value: value > 0 ? value : null,
        ),
      ),
    ),
  ));

  try {
    await updateService.downloadAndInstall(
      update,
      onProgress: (p) => progress.value = p,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not download the update.')),
      );
    }
  } finally {
    progress.dispose();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
