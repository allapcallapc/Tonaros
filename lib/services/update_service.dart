import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// A newer release found on GitHub, ready to be downloaded and installed.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.downloadUrl});

  final String version;
  final String downloadUrl;
}

/// Checks GitHub Releases for a newer build than the one currently
/// installed, then downloads and installs it via the system package
/// installer - the sideload equivalent of a Play Store update, since the
/// app is distributed as a GitHub Release APK rather than through the
/// Play Store (see release-apk.yml).
class UpdateService {
  UpdateService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  static const _channel = MethodChannel('com.tonaros/updates');
  static const _repo = 'allapcallapc/Tonaros';

  final http.Client _httpClient;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<UpdateInfo?> checkForUpdate() async {
    if (!isSupported) return null;
    try {
      final response = await _httpClient
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?)?.trim();
      if (tag == null || tag.isEmpty) return null;
      final latestVersion = tag.startsWith('v') ? tag.substring(1) : tag;

      final assets = (json['assets'] as List?) ?? [];
      final apkAssets = assets
          .cast<Map<String, dynamic>>()
          .where((a) => (a['name'] as String?)?.endsWith('.apk') ?? false);
      final downloadUrl = apkAssets.isEmpty
          ? null
          : apkAssets.first['browser_download_url'] as String?;
      if (downloadUrl == null) return null;

      final currentVersion = (await PackageInfo.fromPlatform()).version;
      if (!_isNewer(latestVersion, currentVersion)) return null;

      return UpdateInfo(version: latestVersion, downloadUrl: downloadUrl);
    } catch (e) {
      return null;
    }
  }

  bool _isNewer(String latest, String current) {
    final latestParts = _parseVersion(latest);
    final currentParts = _parseVersion(current);
    for (var i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l != c) return l > c;
    }
    return false;
  }

  List<int> _parseVersion(String version) => version
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  /// Downloads [update]'s APK to the app's cache dir and hands it to the
  /// system package installer. [onProgress] reports 0.0-1.0 when the server
  /// provides a content length (GitHub Releases always does).
  Future<void> downloadAndInstall(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final apkDir = Directory('${cacheDir.path}/apk_updates');
    if (!await apkDir.exists()) {
      await apkDir.create(recursive: true);
    }
    final file = File('${apkDir.path}/tonaros-update.apk');

    final request = http.Request('GET', Uri.parse(update.downloadUrl));
    final streamedResponse = await _httpClient.send(request);
    if (streamedResponse.statusCode != 200) {
      // Drain the body so the connection can be reused, and don't hand an
      // error page to the package installer as if it were an APK.
      await streamedResponse.stream.drain<void>();
      throw HttpException(
        'APK download failed with HTTP ${streamedResponse.statusCode}',
        uri: request.url,
      );
    }
    final total = streamedResponse.contentLength ?? 0;
    var received = 0;

    final sink = file.openWrite();
    try {
      await streamedResponse.stream.map((chunk) {
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
        return chunk;
      }).pipe(sink);
    } finally {
      await sink.close();
    }

    await _channel.invokeMethod('installApk', {'filePath': file.path});
  }

  Future<bool> isInstallPermissionGranted() async {
    if (!isSupported) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('isInstallPermissionGranted');
      return granted ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> openInstallPermissionSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (e) {
      // Ignore - user will see nothing happen and can retry.
    }
  }
}
