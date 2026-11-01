import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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

  /// Whether the notification would look the same with [other] shown: equal
  /// (see [==]) once countdowns no more than [tolerance] apart are taken as
  /// the same (the system draws the countdown from the wall clock, so a
  /// small drift isn't worth an update).
  bool looksLike(BackgroundStatus other,
          {Duration tolerance = Duration.zero}) =>
      title == other.title &&
      text == other.text &&
      action == other.action &&
      _countdownCloseTo(other.endsAt, tolerance: tolerance);

  /// Whether [endsAt] and [end] are both null, or no more than [tolerance]
  /// apart.
  bool _countdownCloseTo(DateTime? end, {Duration tolerance = Duration.zero}) {
    final mine = endsAt;
    if (mine == null || end == null) return mine == end;
    return mine.difference(end).abs() <= tolerance;
  }

  @override
  bool operator ==(Object other) =>
      other is BackgroundStatus && looksLike(other);

  @override
  int get hashCode => Object.hash(title, text, endsAt, action);
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
  PlatformBackgroundSession({bool Function()? isInForeground})
      : _isInForeground = isInForeground ?? _appIsResumed;

  static bool _appIsResumed() =>
      SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Whether the app is in the foreground, where a native start can work.
  final bool Function() _isInForeground;

  static const _channel = MethodChannel('com.tonaros/session');

  static bool get isSupported => isAndroidApp;

  /// The instance whose session the service is running. There is one
  /// service and one channel for the whole app, so an instance that has
  /// been superseded (e.g. a running screen disposed after the next one
  /// started) must leave them alone.
  static PlatformBackgroundSession? _owner;

  /// Whether the last native start was refused, so the service isn't
  /// running and updates would be ignored. Not retried by updates: a
  /// refusal usually means the app was in the background, where Android 12+
  /// refuses every start, so retrying on each would only fail. Retried by
  /// [ensureStarted] on resume, or at once if the refusal is reported while
  /// the app is already in the foreground (see [_onStartFailed]).
  bool _startFailed = false;

  /// The native start in flight, if any: a second start while one is
  /// pending would only queue a second startForegroundService.
  Future<void>? _starting;

  /// Whether a refusal reported while in the foreground was already retried
  /// since the last [ensureStarted] (i.e. resume): a refusal that isn't about
  /// the background (e.g. the service type is rejected) would otherwise be
  /// retried in a loop.
  bool _retriedInForeground = false;

  /// What the notification should show: the last start or update, also while
  /// not started, for a retry.
  BackgroundStatus? _latest;

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
          // Refused after 'start' had succeeded (the app went to the
          // background before the service got going).
          case 'startFailed':
            _onStartFailed();
        }
      });
    }
    return _start(status);
  }

  /// Starts the native side, or joins the start already in flight.
  Future<void> _start(BackgroundStatus status) {
    _latest = status;
    return _starting ??= () async {
      try {
        final started = await _call('start', status);
        // Stopped or superseded meanwhile: nothing left to retry.
        if (_owner != this) return;
        _startFailed = !started;
      } finally {
        _starting = null;
      }
    }();
  }

  /// The service was refused after 'start' had succeeded (e.g. the app went
  /// to the background before it got going). Retried at once if the app is
  /// in the foreground again, since nothing else would until the next
  /// resume; otherwise by [ensureStarted] on that resume.
  void _onStartFailed() {
    if (_owner != this) return;
    _startFailed = true;
    final latest = _latest;
    if (latest != null && !_retriedInForeground && _isInForeground()) {
      _retriedInForeground = true;
      // Not awaited: this only reports the refusal to native.
      _start(latest);
    }
  }

  @override
  Future<void> update(BackgroundStatus status) async {
    if (_owner != this) return;
    _latest = status;
    // Not started: retried by ensureStarted once back in the foreground.
    if (_startFailed) return;
    await _call('update', status);
  }

  @override
  Future<void> ensureStarted(BackgroundStatus status) async {
    if (_owner != this) return;
    _retriedInForeground = false;
    // A start in flight: it decides whether a retry is needed.
    final starting = _starting;
    if (starting != null) {
      await starting;
      // Refused all the same: once more, now from the foreground.
      if (_owner != this || !_startFailed) return;
    } else if (!_startFailed) {
      return;
    }
    return _start(status);
  }

  @override
  Future<void> stop() async {
    if (_owner != this) return;
    _owner = null;
    _startFailed = false;
    _retriedInForeground = false;
    _latest = null;
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
