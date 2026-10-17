import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../file_preview/file_preview_fakes.dart';
import 'image_text_fakes.dart';

PreviewFile _file(String name, String mime) => PreviewFile(
  bucket: 'chat-files',
  path: 'conversation-1/$name',
  name: name,
  mimeType: mime,
  size: 2048,
  messageId: 'message-$name',
  conversationId: 'conversation-1',
);

Future<void> _openViewer(
  WidgetTester tester,
  PreviewFile file,
  ImageTextWorld world,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...filePreviewOverrides(
          fetcher: FakeFileFetcher(
            contents: {file.path: 'x'},
            onDisk: false,
          ),
        ),
        ...world.overrides,
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(openFilePreview(context, file: file)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the picture viewer has Copy text from picture', (tester) async {
    final world = ImageTextWorld();
    await _openViewer(tester, _file('sign.png', 'image/png'), world);
    expect(find.byKey(const ValueKey('file-preview-copy-text')), findsOneWidget);
    expect(find.byTooltip('Copy text from picture'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('file-preview-copy-text')));
    await tester.pumpAndSettle();
    // The sheet shows what the recognizer read from the viewed picture.
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('image-text-field')),
    );
    expect(field.controller!.text, startsWith('Opening hours'));
    expect(world.fetched, ['chat-files/conversation-1/sign.png']);
    expect(
      world.cache.entries.keys,
      contains('m:message-sign.png'),
      reason: 'kept per message',
    );
  });

  testWidgets('on the web the viewer says it needs the apps', (tester) async {
    final world = ImageTextWorld(supported: false);
    await _openViewer(tester, _file('sign.png', 'image/png'), world);
    await tester.tap(find.byKey(const ValueKey('file-preview-copy-text')));
    await tester.pumpAndSettle();
    expect(find.text('Available in the iPhone and Mac apps'), findsOneWidget);
    expect(world.fetched, isEmpty);
  });

  testWidgets('other files do not offer it', (tester) async {
    final world = ImageTextWorld();
    await _openViewer(tester, _file('notes.txt', 'text/plain'), world);
    expect(find.byKey(const ValueKey('file-preview-copy-text')), findsNothing);
  });

  testWidgets('SVG drawings do not offer it either', (tester) async {
    final world = ImageTextWorld();
    await _openViewer(tester, _file('logo.svg', 'image/svg+xml'), world);
    expect(find.byKey(const ValueKey('file-preview-copy-text')), findsNothing);
  });
}
