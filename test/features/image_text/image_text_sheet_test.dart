import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/image_text/image_text_models.dart';
import 'package:wecord/features/image_text/image_text_sheet.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'image_text_fakes.dart';

Future<void> _open(
  WidgetTester tester,
  ImageTextWorld world, {
  String messageId = 'message-1',
  bool dark = false,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: world.overrides,
      child: MaterialApp(
        theme: dark ? WeCordTheme.dark() : WeCordTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => unawaited(
                  showImageTextSheet(
                    context,
                    file: testPicture(messageId: messageId),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

/// Records what is copied to the clipboard.
List<String> _watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('reads the picture and shows the text', (tester) async {
    final world = ImageTextWorld();
    await _open(tester, world);
    expect(find.text('Text from picture'), findsWidgets);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('image-text-field')),
    );
    expect(field.controller!.text, 'Opening hours\nMon–Fri 9:00–18:00\n周末休息');
    // The picture was fetched once and read from that file.
    expect(world.fetched, ['chat-images/conversation-1/message-1.jpg']);
    expect(world.recognizer.paths, ['/cache/sign.jpg']);
    expect(
      find.text('Read on your device. The picture was not uploaded.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a spinner while it reads', (tester) async {
    final world = ImageTextWorld();
    world.recognizer.gate = Completer<void>();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: world.overrides,
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: ImageTextSheet(file: testPicture()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('image-text-loading')), findsOneWidget);
    expect(find.text('Reading the picture…'), findsOneWidget);
    world.recognizer.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-text-loading')), findsNothing);
    expect(find.byKey(const ValueKey('image-text-field')), findsOneWidget);
  });

  testWidgets('Copy puts the text on the clipboard and says so', (
    tester,
  ) async {
    final copied = _watchClipboard(tester);
    final world = ImageTextWorld();
    await _open(tester, world);
    await tester.tap(find.byKey(const ValueKey('image-text-copy')));
    await tester.pump();
    expect(copied, ['Opening hours\nMon–Fri 9:00–18:00\n周末休息']);
    expect(find.text('Copied'), findsOneWidget);
    // The confirmation fades after a moment.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copied'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('Select selects all of the text', (tester) async {
    final world = ImageTextWorld();
    await _open(tester, world);
    await tester.tap(find.byKey(const ValueKey('image-text-select')));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('image-text-field')),
    );
    final controller = field.controller!;
    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.text.length);
    expect(field.focusNode!.hasFocus, isTrue);
    // The field is read-only: it can be selected, not changed.
    expect(field.readOnly, isTrue);
  });

  testWidgets('Translate is not offered without AI', (tester) async {
    final world = ImageTextWorld();
    await _open(tester, world);
    expect(find.byKey(const ValueKey('image-text-translate')), findsNothing);
    expect(find.byKey(const ValueKey('image-text-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-text-select')), findsOneWidget);
  });

  testWidgets('Translate shows the translation, which can be copied', (
    tester,
  ) async {
    final copied = _watchClipboard(tester);
    final world = ImageTextWorld(aiOn: true);
    world.ai.translated = '营业时间';
    await _open(tester, world);
    await tester.tap(find.byKey(const ValueKey('image-text-translate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-text-translation')), findsOne);
    expect(find.text('营业时间'), findsOneWidget);
    expect(find.text('Translated to English'), findsOneWidget);
    // It translates the recognized text into the app's language.
    expect(world.ai.translateCalls.single.text, contains('Opening hours'));
    expect(world.ai.translateCalls.single.target, AiLanguage.appLanguage);

    await tester.tap(find.byKey(const ValueKey('image-text-copy-translation')));
    await tester.pump();
    expect(copied.last, '营业时间');
  });

  testWidgets('a translation that fails says why', (tester) async {
    final world = ImageTextWorld(aiOn: true);
    world.ai.error = const AiLimitReachedException(limit: 50);
    await _open(tester, world);
    await tester.tap(find.byKey(const ValueKey('image-text-translate')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('image-text-translate-error')),
      findsOneWidget,
    );
    expect(find.textContaining('AI limit of 50'), findsOneWidget);
    // The text is still there to copy.
    expect(find.byKey(const ValueKey('image-text-copy')), findsOneWidget);
  });

  testWidgets('remembers the text per message', (tester) async {
    final world = ImageTextWorld();
    await _open(tester, world);
    final saved = world.cache.entries['m:message-1'];
    expect(saved?.text, 'Opening hours\nMon–Fri 9:00–18:00\n周末休息');

    // Opening it again reads nothing and downloads nothing.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    world.recognizer.lines = const ['Something else'];
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(world.recognizer.paths.length, 1);
    expect(world.fetched.length, 1);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('image-text-field')),
    );
    expect(field.controller!.text, startsWith('Opening hours'));
  });

  testWidgets('another message is read on its own', (tester) async {
    final world = ImageTextWorld();
    await world.cache.write(
      'm:other',
      CachedImageText(text: 'Cached words', savedAt: DateTime.utc(2026)),
    );
    await _open(tester, world, messageId: 'other');
    expect(world.recognizer.paths, isEmpty);
    expect(world.fetched, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('image-text-field')))
          .controller!
          .text,
      'Cached words',
    );
  });

  testWidgets('a picture without text says so, and it is remembered', (
    tester,
  ) async {
    final world = ImageTextWorld();
    world.recognizer.lines = const [];
    await _open(tester, world);
    expect(find.byKey(const ValueKey('image-text-none')), findsOneWidget);
    expect(find.text('No text found in this picture'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-text-copy')), findsNothing);
    expect(world.cache.entries['m:message-1']?.text, '');

    // Next time it is known without reading again.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-text-none')), findsOneWidget);
    expect(world.recognizer.paths.length, 1);
  });

  testWidgets('a failure can be tried again', (tester) async {
    final world = ImageTextWorld();
    world.recognizer.error = const ImageTextException(ImageTextFailure.failed);
    await _open(tester, world);
    expect(find.byKey(const ValueKey('image-text-failed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-text-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-text-field')), findsOneWidget);
    expect(world.recognizer.paths.length, 2);
  });

  testWidgets('a picture the system cannot open is explained', (tester) async {
    final world = ImageTextWorld();
    world.recognizer.error = const ImageTextException(
      ImageTextFailure.unreadable,
    );
    await _open(tester, world);
    expect(find.byKey(const ValueKey('image-text-unreadable')), findsOneWidget);
  });

  testWidgets('without a recognizer (the web) nothing is read or downloaded', (
    tester,
  ) async {
    final world = ImageTextWorld(supported: false);
    await _open(tester, world);
    expect(
      find.byKey(const ValueKey('image-text-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Available in the iPhone and Mac apps'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-text-copy')), findsNothing);
    expect(world.fetched, isEmpty, reason: 'the picture is never downloaded');
    expect(world.recognizer.paths, isEmpty);
    expect(world.cache.entries, isEmpty);
    expect(world.ai.translateCalls, isEmpty);
  });

  testWidgets('works in the dark theme on a wide window', (tester) async {
    final world = ImageTextWorld(aiOn: true);
    await _open(tester, world, dark: true, size: const Size(1280, 800));
    expect(find.byKey(const ValueKey('image-text-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-text-translate')), findsOneWidget);
  });
}
