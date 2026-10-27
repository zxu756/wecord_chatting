import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('wecord/on_device_ai');
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const backend = NativeOnDeviceAiBackend();

  group('availability', () {
    test('is available', () async {
      answer((_) async => {'available': true, 'reason': ''});
      expect(await backend.availability(), const OnDeviceAiStatus.available());
    });

    final reasons = {
      'os_too_old': OnDeviceAiUnavailable.osTooOld,
      'device_not_eligible': OnDeviceAiUnavailable.deviceNotEligible,
      'not_enabled': OnDeviceAiUnavailable.notEnabled,
      'model_not_ready': OnDeviceAiUnavailable.modelNotReady,
      'unavailable': OnDeviceAiUnavailable.unknown,
      'something new': OnDeviceAiUnavailable.unknown,
    };
    for (final MapEntry(key: code, value: reason) in reasons.entries) {
      test('says why not: $code', () async {
        answer((_) async => {'available': false, 'reason': code});
        final status = await backend.availability();
        expect(status.available, isFalse);
        expect(status.reason, reason);
      });
    }

    test('a platform without the plugin is unsupported', () async {
      // No handler: the channel throws MissingPluginException.
      final status = await backend.availability();
      expect(status.reason, OnDeviceAiUnavailable.unsupportedPlatform);
    });

    test('a failing check reads as unavailable, never throws', () async {
      answer((_) async => throw PlatformException(code: 'boom'));
      expect((await backend.availability()).available, isFalse);
    });
  });

  group('requests', () {
    test('summarize sends the lines, language and flags', () async {
      answer((_) async => {'text': '  - A\n- B  '});
      final text = await backend.summarize(
        lines: ['Ana: hi'],
        language: AiLanguage.chinese,
        recent: true,
        merge: true,
      );
      expect(text, '- A\n- B');
      expect(calls.single.method, 'summarize');
      expect(calls.single.arguments, {
        'lines': ['Ana: hi'],
        'language': 'zh',
        'recent': true,
        'merge': true,
      });
    });

    test('rewrite and translate send their arguments', () async {
      answer((_) async => {'text': 'done'});
      await backend.rewrite(mode: AiRewriteMode.formal, text: 'yo');
      await backend.translate(text: 'hi', target: AiLanguage.french);
      expect(calls[0].arguments, {'mode': 'formal', 'text': 'yo'});
      expect(calls[1].method, 'translate');
      expect(calls[1].arguments, {'text': 'hi', 'target': 'fr'});
    });

    test('an empty answer is a failure', () async {
      answer((_) async => {'text': '  '});
      await expectLater(
        backend.translate(text: 'hi', target: AiLanguage.english),
        throwsA(isA<OnDeviceAiFailedException>()),
      );
    });

    test('unavailable carries the reason', () async {
      answer(
        (_) async => throw PlatformException(
          code: 'unavailable',
          message: 'not_enabled',
        ),
      );
      await expectLater(
        backend.translate(text: 'hi', target: AiLanguage.english),
        throwsA(
          isA<OnDeviceAiUnavailableException>().having(
            (e) => e.reason,
            'reason',
            OnDeviceAiUnavailable.notEnabled,
          ),
        ),
      );
    });

    final failures = {
      'context_too_long': OnDeviceAiFailureKind.tooLong,
      'refused': OnDeviceAiFailureKind.refused,
      'unsupported_language': OnDeviceAiFailureKind.language,
      'busy': OnDeviceAiFailureKind.busy,
      'failed': OnDeviceAiFailureKind.failed,
      'weird': OnDeviceAiFailureKind.failed,
    };
    for (final MapEntry(key: code, value: kind) in failures.entries) {
      test('a $code error is $kind', () async {
        answer((_) async => throw PlatformException(code: code));
        await expectLater(
          backend.rewrite(mode: AiRewriteMode.fix, text: 'x'),
          throwsA(
            isA<OnDeviceAiFailedException>().having(
              (e) => e.kind,
              'kind',
              kind,
            ),
          ),
        );
      });
    }

    test('no plugin means unavailable', () async {
      await expectLater(
        backend.rewrite(mode: AiRewriteMode.fix, text: 'x'),
        throwsA(isA<OnDeviceAiUnavailableException>()),
      );
    });
  });

  test('the platforms without a model say so', () async {
    const none = NoOnDeviceAiBackend();
    expect(none.isSupportedPlatform, isFalse);
    expect(
      (await none.availability()).reason,
      OnDeviceAiUnavailable.unsupportedPlatform,
    );
    await expectLater(
      none.translate(text: 'x', target: AiLanguage.english),
      throwsA(isA<OnDeviceAiUnavailableException>()),
    );
  });

  test(
    'the test platform is not an Apple one, so the web/Android default is none',
    () {
      // flutter test runs as Android by default: the provider picks no model.
      expect(defaultTargetPlatform, isNot(TargetPlatform.iOS));
    },
  );

  group('native sources', () {
    // The iPhone and Mac apps compile the same Swift, kept as two copies
    // because each app's Xcode project lists its own files.
    for (final name in ['OnDeviceAiCore.swift', 'OnDeviceAiPlugin.swift']) {
      test('$name is the same in the iOS and macOS apps', () {
        expect(
          File('ios/Runner/$name').readAsStringSync(),
          File('macos/Runner/$name').readAsStringSync(),
        );
      });
    }

    test('the plugin is registered in both apps', () {
      expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        contains('OnDeviceAiPlugin.register'),
      );
      expect(
        File('macos/Runner/MainFlutterWindow.swift').readAsStringSync(),
        contains('OnDeviceAiPlugin.register'),
      );
    });

    test('both Xcode projects build the two files', () {
      for (final project in [
        'ios/Runner.xcodeproj/project.pbxproj',
        'macos/Runner.xcodeproj/project.pbxproj',
      ]) {
        final text = File(project).readAsStringSync();
        expect(text, contains('OnDeviceAiCore.swift in Sources'));
        expect(text, contains('OnDeviceAiPlugin.swift in Sources'));
      }
    });

    test('the model is only touched behind an availability check', () {
      final source = File(
        'macos/Runner/OnDeviceAiCore.swift',
      ).readAsStringSync();
      expect(source, contains('#available(iOS 26.0, macOS 26.0, *)'));
      expect(source, contains('canImport(FoundationModels)'));
    });
  });
}
