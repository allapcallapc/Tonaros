import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/services/background_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tonaros/session');
  late List<String> calls;

  /// How many of the next native starts are refused.
  late int startsToRefuse;

  setUp(() {
    calls = [];
    startsToRefuse = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start' && startsToRefuse > 0) {
        startsToRefuse--;
        throw PlatformException(code: 'START_FAILED');
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const status = BackgroundStatus(title: 'S', text: 'Get ready');

  test('a superseded session leaves the newer one running', () async {
    final old = PlatformBackgroundSession();
    final current = PlatformBackgroundSession();
    await old.start(status, onAction: (_) {}, onDismissed: () {});
    await current.start(status, onAction: (_) {}, onDismissed: () {});

    // E.g. the old running screen disposed after the new one started.
    await old.update(status);
    await old.stop();
    expect(calls, ['start', 'start']);

    await current.update(status);
    await current.stop();
    expect(calls, ['start', 'start', 'update', 'stop']);
  });

  test('a refused start is retried on resume, not by updates', () async {
    final session = PlatformBackgroundSession();
    startsToRefuse = 2;
    await session.start(status, onAction: (_) {}, onDismissed: () {});
    // Still in the background: updates don't try (and fail) again.
    await session.update(status);
    expect(calls, ['start']);
    // Refused again: tried again on the next resume.
    await session.ensureStarted(status);
    await session.ensureStarted(status);
    expect(calls, ['start', 'start', 'start']);

    // Running now: back to plain updates, and nothing to retry.
    await session.update(status);
    await session.ensureStarted(status);
    await session.stop();
    expect(calls, ['start', 'start', 'start', 'update', 'stop']);
  });

  test('ensureStarted does nothing once started', () async {
    final session = PlatformBackgroundSession();
    await session.start(status, onAction: (_) {}, onDismissed: () {});
    await session.ensureStarted(status);
    await session.stop();
    await session.ensureStarted(status);
    expect(calls, ['start', 'stop']);
  });

  test('passes on the tapped label and the app being swiped away', () async {
    final session = PlatformBackgroundSession();
    final taps = <String?>[];
    var dismissed = 0;
    await session.start(status,
        onAction: taps.add, onDismissed: () => dismissed++);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    Future<void> fromNative(String method, [Object? arguments]) =>
        messenger.handlePlatformMessage(channel.name,
            codec.encodeMethodCall(MethodCall(method, arguments)), (_) {});
    await fromNative('action', 'Pause');
    await fromNative('dismissed');
    expect(taps, ['Pause']);
    expect(dismissed, 1);
    await session.stop();
  });

  Future<void> fromNative(String method, [Object? arguments]) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
              channel.name,
              const StandardMethodCodec()
                  .encodeMethodCall(MethodCall(method, arguments)),
              (_) {});

  test('a start refused natively after it returned is retried on resume',
      () async {
    final session = PlatformBackgroundSession();
    await session.start(status, onAction: (_) {}, onDismissed: () {});
    await fromNative('startFailed');
    // The service isn't running: updates would be ignored.
    await session.update(status);
    await session.ensureStarted(status);
    await session.stop();
    expect(calls, ['start', 'start', 'stop']);
  });

  test('a start refused after stop leaves nothing to retry', () async {
    final session = PlatformBackgroundSession();
    startsToRefuse = 1;
    final starting =
        session.start(status, onAction: (_) {}, onDismissed: () {});
    await session.stop();
    await starting;
    await session.ensureStarted(status);
    expect(calls, ['start', 'stop']);
  });

  test('looksLike allows a small countdown drift, nothing else', () {
    final at = DateTime(2026);
    final s = BackgroundStatus(title: 'S', text: 'Hold', endsAt: at);
    BackgroundStatus other(
            {String text = 'Hold', DateTime? endsAt, String? action}) =>
        BackgroundStatus(
            title: 'S', text: text, endsAt: endsAt ?? at, action: action);
    const tolerance = Duration(seconds: 1);
    expect(s.looksLike(other(), tolerance: tolerance), isTrue);
    expect(
        s.looksLike(other(endsAt: at.add(const Duration(milliseconds: 900))),
            tolerance: tolerance),
        isTrue);
    expect(
        s.looksLike(other(endsAt: at.add(const Duration(seconds: 2))),
            tolerance: tolerance),
        isFalse);
    expect(s.looksLike(other(text: 'Rest'), tolerance: tolerance), isFalse);
    expect(s.looksLike(other(action: 'Pause'), tolerance: tolerance), isFalse);
    expect(s.looksLike(const BackgroundStatus(title: 'S', text: 'Hold')),
        isFalse);
  });
}
