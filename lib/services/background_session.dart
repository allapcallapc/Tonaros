import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the ongoing "session running" notification shows.
class BackgroundStatus {
  const BackgroundStatus({
    required this.title,
    required this.text,
    this.endsAt,
  });

  final String title;
  final String text;

  /// When the current phase ends, for the notification's live countdown;
  /// null while paused or waiting for a tap.
  final DateTime? endsAt;
}

/// Keeps a running session alive with the app in the background or the
/// screen off, so the timer keeps firing and cues keep playing. On Android
/// this is a foreground service (android/.../SessionService.kt) with an
/// ongoing notification; elsewhere it does nothing.
abstract class BackgroundSession {
  Future<void> start(BackgroundStatus status);
  Future<void> update(BackgroundStatus status);
  Future<void> stop();
}

class PlatformBackgroundSession implements BackgroundSession {
  static const _channel = MethodChannel('com.tonaros/session');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> start(BackgroundStatus status) => _call('start', status);

  @override
  Future<void> update(BackgroundStatus status) => _call('update', status);

  @override
  Future<void> stop() => _call('stop');

  /// Never throws: the session runs on in the foreground regardless.
  Future<void> _call(String method, [BackgroundStatus? status]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, {
        if (status != null) ...{
          'title': status.title,
          'text': status.text,
          'endsAt': status.endsAt?.millisecondsSinceEpoch ?? 0,
        },
      });
    } on Object catch (e) {
      debugPrint('BackgroundSession: $method failed: $e');
    }
  }
}
