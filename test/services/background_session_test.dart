import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/services/background_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tonaros/session');
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
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
    await old.start(status, onAction: () {});
    await current.start(status, onAction: () {});

    // E.g. the old running screen disposed after the new one started.
    await old.update(status);
    await old.stop();
    expect(calls, ['start', 'start']);

    await current.update(status);
    await current.stop();
    expect(calls, ['start', 'start', 'update', 'stop']);
  });
}
