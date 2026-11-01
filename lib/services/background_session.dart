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

  /// What the notification should show: the last status passed in, also
  /// while the service isn't running. Every native start or update sends
  /// this, so nothing is ever posted out of date.
  BackgroundStatus? _desired;

  /// Whether the native side has accepted a start that hasn't been refused
  /// since, so updates can go straight to it. While not, updates are only
  /// recorded in [_desired]: a refusal usually means the app was in the
  /// background, where Android 12+ refuses every start, so retrying on each
  /// update would only fail. A start is retried by [ensureStarted] on
  /// resume, or at once if the refusal is reported while the app is already
  /// in the foreground (see [_onStartFailed]).
  bool _started = false;

  /// The native start in flight, if any: every start joins it rather than
  /// queue a second startForegroundService.
  Future<void>? _starting;

  /// Whether a refusal reported in the foreground was already retried since
  /// the last [ensureStarted] (i.e. resume): one that isn't about the
  /// background (e.g. a rejected service type) would otherwise be retried
  /// in a loop.
  bool _retriedInForeground = false;

  @override
  Future<void> start(
    BackgroundStatus status, {
    required ValueChanged<String?> onAction,
    required VoidCallback onDismissed,
  }) {
    _owner = this;
    _desired = status;
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
    return _start();
  }

  /// Starts the native side with [_desired], or joins the start in flight.
  Future<void> _start() {
    final pending = _starting;
    if (pending != null) return pending;
    late final Future<void> starting;
    starting = _startOnce().whenComplete(() {
      if (identical(_starting, starting)) _starting = null;
    });
    return _starting = starting;
  }

  Future<void> _startOnce() async {
    var sent = _desired;
    if (sent == null) return;
    final started = await _call('start', sent);
    // Stopped or superseded meanwhile: nothing left to do.
    if (_owner != this) return;
    _started = started;
    // Updated while starting (only recorded then): catch up, until nothing
    // newer came in meanwhile.
    while (_started && _owner == this) {
      final desired = _desired;
      if (desired == null || desired == sent) break;
      sent = desired;
      await _call('update', desired);
    }
  }

  /// The service was refused after 'start' had succeeded. Retried at once
  /// if the app is in the foreground, since nothing else would until the
  /// next resume; otherwise by [ensureStarted] on that resume.
  void _onStartFailed() {
    if (_owner != this) return;
    _started = false;
    if (!_retriedInForeground && _isInForeground()) {
      _retriedInForeground = true;
      // Not awaited: this only reports the refusal to native.
      _start();
    }
  }

  @override
  Future<void> update(BackgroundStatus status) async {
    if (_owner != this) return;
    _desired = status;
    // Not started (or still starting): sent by the next start.
    if (!_started || _starting != null) return;
    await _call('update', status);
  }

  @override
  Future<void> ensureStarted(BackgroundStatus status) async {
    if (_owner != this) return;
    _desired = status;
    _retriedInForeground = false;
    // A start in flight: wait for it, then retry if it was refused.
    final pending = _starting;
    if (pending != null) await pending;
    if (_owner != this || _started) return;
    return _start();
  }

  @override
  Future<void> stop() async {
    if (_owner != this) return;
    _owner = null;
    _desired = null;
    _started = false;
    _retriedInForeground = false;
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
