import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

/// The Runner apps' `VoiceInputPlugin` as the Dart side sees it: a method
/// channel and an event channel. The test plays the native side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel('wecord/voice_input');
  const events = EventChannel('wecord/voice_input/events');

  late List<MethodCall> calls;
  MockStreamHandlerEventSink? sink;
  Object? Function(MethodCall call)? onCall;

  setUp(() {
    calls = [];
    sink = null;
    onCall = null;
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      final handler = onCall;
      if (handler != null) {
        final answer = handler(call);
        if (answer is Exception) {
          throw answer;
        }
        return answer;
      }
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, eventSink) => sink = eventSink,
        onCancel: (arguments) => sink = null,
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('it reads what the system recognizer can do', () async {
    onCall = (call) => {
      'supported': true,
      'available': true,
      'onDevice': false,
      'locale': 'zh_CN',
      'authorization': 'notDetermined',
      'microphone': 'notDetermined',
    };
    final recognizer = NativeVoiceRecognizer();
    final capabilities = await recognizer.capabilities('zh-CN');
    expect(calls.single.method, 'capabilities');
    expect(calls.single.arguments, {'locale': 'zh-CN'});
    expect(capabilities.supported, isTrue);
    expect(capabilities.usable, isTrue);
    expect(capabilities.engine, VoiceInputEngine.appleServer);

    onCall = (call) => {'supported': true, 'available': true, 'onDevice': true};
    expect(
      (await recognizer.capabilities('en-US')).engine,
      VoiceInputEngine.onDevice,
    );
    onCall = (call) => {'supported': false};
    expect((await recognizer.capabilities('xx')).supported, isFalse);
  });

  test('a missing plugin means no support', () async {
    messenger.setMockMethodCallHandler(method, null);
    final capabilities = await NativeVoiceRecognizer().capabilities('en-US');
    expect(capabilities.supported, isFalse);
  });

  test('a session turns native events into recognizer events', () async {
    final recognizer = NativeVoiceRecognizer();
    final session = await recognizer.start(locale: 'en-US', allowServer: false);
    expect(calls.single.method, 'start');
    expect(calls.single.arguments, {'locale': 'en-US', 'allowServer': false});

    final received = <VoiceInputEvent>[];
    session.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);
    expect(sink, isNotNull, reason: 'the event channel is listened to');
    sink!.success({'type': 'partial', 'text': 'hel'});
    sink!.success({'type': 'level', 'value': 0.4});
    sink!.success({'type': 'final', 'text': 'hello'});
    sink!.success({'type': 'end'});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received[0], isA<VoicePartial>());
    expect((received[0] as VoicePartial).text, 'hel');
    expect((received[1] as VoiceLevel).value, 0.4);
    expect((received[2] as VoiceFinal).text, 'hello');
    expect(received[3], isA<VoiceEnded>());
  });

  test('stop and cancel reach the native side', () async {
    final recognizer = NativeVoiceRecognizer();
    final session = await recognizer.start(locale: 'en-US', allowServer: true);
    await session.stop();
    expect(calls.last.method, 'stop');

    final other = await recognizer.start(locale: 'en-US', allowServer: true);
    await other.cancel();
    expect(calls.last.method, 'cancel');
  });

  test('events of a finished session do not leak into the next', () async {
    final recognizer = NativeVoiceRecognizer();
    final first = await recognizer.start(locale: 'en-US', allowServer: false);
    final firstEvents = <VoiceInputEvent>[];
    first.events.listen(firstEvents.add);
    await Future<void>.delayed(Duration.zero);
    sink!.success({'type': 'end'});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final second = await recognizer.start(locale: 'en-US', allowServer: false);
    final secondEvents = <VoiceInputEvent>[];
    second.events.listen(secondEvents.add);
    sink!.success({'type': 'partial', 'text': 'new'});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(firstEvents.whereType<VoicePartial>(), isEmpty);
    expect(secondEvents.whereType<VoicePartial>().single.text, 'new');
  });

  test('refusals from the system become failures', () async {
    final recognizer = NativeVoiceRecognizer();
    Future<VoiceInputException> failWith(String code) async {
      onCall = (call) => PlatformException(code: code);
      try {
        await recognizer.start(locale: 'en-US', allowServer: false);
      } on VoiceInputException catch (error) {
        return error;
      }
      throw StateError('start did not fail');
    }

    expect(
      (await failWith('not_authorized')).failure,
      VoiceInputFailure.speechDenied,
    );
    expect((await failWith('mic_denied')).failure, VoiceInputFailure.micDenied);
    expect(
      (await failWith('unsupported_locale')).failure,
      VoiceInputFailure.unsupportedLanguage,
    );
    expect(
      (await failWith('unavailable')).failure,
      VoiceInputFailure.unavailable,
    );
    expect((await failWith('failed')).failure, VoiceInputFailure.failed);
    final needsServer = await failWith('needs_server');
    expect(needsServer.needsServer, isTrue);
  });
}
