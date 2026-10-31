import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the ongoing "session running" notification shows.
class BackgroundStatus {
  const BackgroundStatus({
    required this.title,
    required this.text,
    this.endsAt,
    this.action,
  });

  final String title;
  final String text;

  /// When the current phase ends, for the notification's live countdown;
  /// null while paused or waiting for a tap. Also whether the CPU is kept
  /// awake: only while there's a countdown for the timer to follow.
  final DateTime? endsAt;

  /// The label of the notification's button ("Pause", "Resume",
  /// "Continue"), which mirrors the running screen's main button; none if
  /// null.
  final String? action;
}

/// Keeps a running session alive with the app in the background or the
/// screen off, so the timer keeps firing and cues keep playing. On Android
/// this is a foreground service (android/.../SessionService.kt) with an
/// ongoing notification; elsewhere it does nothing.
abstract class BackgroundSession {
  /// Starts it; [onAction] runs when the notification's button is tapped.
  Future<void> start(BackgroundStatus status, {required VoidCallback onAction});
  Future<void> update(BackgroundStatus status);
  Future<void> stop();
}

class PlatformBackgroundSession implements BackgroundSession {
  static const _channel = MethodChannel('com.tonaros/session');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The instance whose session the service is running. There is one
  /// service and one channel for the whole app, so an instance that has
  /// been superseded (e.g. a running screen disposed after the next one
  /// started) must leave them alone.
  static PlatformBackgroundSession? _owner;

  @override
  Future<void> start(BackgroundStatus status,
      {required VoidCallback onAction}) {
    _owner = this;
    if (isSupported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'action') onAction();
      });
    }
    return _call('start', status);
  }

  @override
  Future<void> update(BackgroundStatus status) async {
    if (_owner != this) return;
    return _call('update', status);
  }

  @override
  Future<void> stop() async {
    if (_owner != this) return;
    _owner = null;
    if (isSupported) _channel.setMethodCallHandler(null);
    return _call('stop');
  }

  /// Never throws: the session runs on in the foreground regardless.
  Future<void> _call(String method, [BackgroundStatus? status]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, {
        if (status != null) ...{
          'title': status.title,
          'text': status.text,
          'endsAt': status.endsAt?.millisecondsSinceEpoch ?? 0,
          'action': status.action,
        },
      });
    } on Object catch (e) {
      debugPrint('BackgroundSession: $method failed: $e');
    }
  }
}
