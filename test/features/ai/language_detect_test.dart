import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/language_detect.dart';

void main() {
  group('roughLanguage', () {
    test('tells the CJK scripts by their letters', () {
      expect(roughLanguage('你好，大家好'), RoughLanguage.chinese);
      expect(roughLanguage('こんにちは、元気ですか'), RoughLanguage.japanese);
      expect(roughLanguage('今日は天気がいいですね'), RoughLanguage.japanese);
      expect(roughLanguage('안녕하세요 여러분'), RoughLanguage.korean);
    });

    test('Latin text is Latin whatever the language', () {
      expect(roughLanguage('hello there'), RoughLanguage.latin);
      expect(roughLanguage('hola, ¿qué tal?'), RoughLanguage.latin);
      expect(roughLanguage('Ça va très bien'), RoughLanguage.latin);
    });

    test('other scripts are other', () {
      expect(roughLanguage('Привет'), RoughLanguage.other);
    });

    test('no letters means nothing to translate', () {
      expect(roughLanguage('😀🎉'), RoughLanguage.none);
      expect(roughLanguage('https://example.com/a?b=1'), RoughLanguage.none);
      expect(roughLanguage('@ana @bob_2'), RoughLanguage.none);
      expect(roughLanguage('12:30 !!! 100%'), RoughLanguage.none);
      expect(roughLanguage(''), RoughLanguage.none);
    });

    test('links and mentions do not decide the language', () {
      expect(
        roughLanguage('看看 https://example.com/english-page @ana'),
        RoughLanguage.chinese,
      );
      expect(roughLanguage('@ana 你好'), RoughLanguage.chinese);
    });

    test('a mixed text goes with the larger part', () {
      expect(roughLanguage('see 你'), RoughLanguage.latin);
      expect(roughLanguage('今天我 meet'), RoughLanguage.other);
    });
  });

  group('worthTranslating', () {
    test('skips text that has no letters', () {
      expect(worthTranslating('🙂', AiLanguage.english), isFalse);
      expect(worthTranslating('https://a.test', AiLanguage.english), isFalse);
      expect(worthTranslating('@ana', AiLanguage.english), isFalse);
      expect(worthTranslating('   ', AiLanguage.english), isFalse);
    });

    test('skips text already in the target language', () {
      expect(worthTranslating('你好啊', AiLanguage.chinese), isFalse);
      expect(worthTranslating('こんにちは', AiLanguage.japanese), isFalse);
      expect(worthTranslating('你好啊', AiLanguage.english), isTrue);
      expect(worthTranslating('你好啊', AiLanguage.japanese), isTrue);
    });

    test('leaves Latin text to the server (English or Spanish?)', () {
      expect(worthTranslating('hola', AiLanguage.english), isTrue);
      expect(worthTranslating('hello', AiLanguage.english), isTrue);
    });

    test('skips languages the person does not translate', () {
      expect(
        worthTranslating(
          '你好啊',
          AiLanguage.english,
          skipLanguages: {AiLanguage.chinese},
        ),
        isFalse,
      );
      expect(
        worthTranslating(
          'こんにちは',
          AiLanguage.english,
          skipLanguages: {AiLanguage.chinese},
        ),
        isTrue,
      );
    });

    test('leaves a very long message to the message menu', () {
      expect(worthTranslating('a' * 1500, AiLanguage.chinese), isTrue);
      expect(worthTranslating('a' * 1501, AiLanguage.chinese), isFalse);
    });
  });
}
