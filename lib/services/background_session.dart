import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

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

  /// Whether the notification would look the same with [other] shown: the
  /// same text and button, and countdowns no more than [tolerance] apart
  /// (the system draws the countdown from the wall clock, so a small drift
  /// isn't worth an update). Compares every field, so a field added here
  /// must be added below too.
  bool looksLike(BackgroundStatus other,
      {Duration tolerance = Duration.zero}) {
    final end = endsAt;
    final otherEnd = other.endsAt;
    final sameCountdown = (end == null && otherEnd == null) ||
        (end != null &&
            otherEnd != null &&
            end.difference(otherEnd).abs() <= tolerance);
    return title == other.title &&
        text == other.text &&
        action == other.action &&
        sameCountdown;
  }
}

/// Keeps a running session alive with the app in the background or the
/// screen off, so the timer keeps firing and cues keep playing. On Android
/// this is a foreground service (android/.../SessionService.kt) with an
/// ongoing notification; elsewhere it does nothing.
abstract class BackgroundSession {
  /// Starts it. [onAction] runs when the notification's button is tapped,
  /// with the label the tapped button showed (null if unknown), so a tap on
  /// a label that is already out of date can be ignored. [onDismissed] runs
  /// when the app is swiped away from recents, which ends the session.
  Future<void> start(
    BackgroundStatus status, {
    required ValueChanged<String?> onAction,
    required VoidCallback onDismissed,
  });
  Future<void> update(BackgroundStatus status);

  /// Called when the app comes back to the foreground: starts it again if
  /// [start] was refused (e.g. the app went to the background before the
  /// service could start), which only works from the foreground.
  Future<void> ensureStarted(BackgroundStatus status);

  Future<void> stop();
}

class PlatformBackgroundSession implements BackgroundSession {
  static const _channel = MethodChannel('com.tonaros/session');

  static bool get isSupported => isAndroidApp;

  /// The instance whose session the service is running. There is one
  /// service and one channel for the whole app, so an instance that has
  /// been superseded (e.g. a running screen disposed after the next one
  /// started) must leave them alone.
  static PlatformBackgroundSession? _owner;

  /// Whether the last native start was refused, so the service isn't
  /// running and updates would be ignored. Only [ensureStarted] tries again:
  /// a refusal means the app was in the background, where Android 12+
  /// refuses every start, so retrying on each update would only fail.
  bool _startFailed = false;

  @override
  Future<void> start(
    BackgroundStatus status, {
    required ValueChanged<String?> onAction,
    required VoidCallback onDismissed,
  }) {
    _owner = this;
    if (isSupported) {
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'action':
            onAction(call.arguments as String?);
          case 'dismissed':
            onDismissed();
        }
      });
    }
    return _start(status);
  }

  Future<void> _start(BackgroundStatus status) async {
    _startFailed = !await _call('start', status);
  }

  @override
  Future<void> update(BackgroundStatus status) async {
    // Not started: retried by ensureStarted once back in the foreground.
    if (_owner != this || _startFailed) return;
    await _call('update', status);
  }

  @override
  Future<void> ensureStarted(BackgroundStatus status) async {
    if (_owner != this || !_startFailed) return;
    return _start(status);
  }

  @override
  Future<void> stop() async {
    if (_owner != this) return;
    _owner = null;
    _startFailed = false;
    if (isSupported) _channel.setMethodCallHandler(null);
    await _call('stop');
  }

  /// Whether the call succeeded (always, off Android). Never throws: the
  /// session runs on in the foreground regardless.
  Future<bool> _call(String method, [BackgroundStatus? status]) async {
    if (!isSupported) return true;
    try {
      await _channel.invokeMethod<void>(method, {
        if (status != null) ...{
          'title': status.title,
          'text': status.text,
          'endsAt': status.endsAt?.millisecondsSinceEpoch ?? 0,
          'action': status.action,
        },
      });
      return true;
    } on Object catch (e) {
      debugPrint('BackgroundSession: $method failed: $e');
      return false;
    }
  }
}
