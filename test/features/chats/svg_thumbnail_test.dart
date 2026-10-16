// SVG files in chat show a drawing of themselves at the top of their card,
// like PDFs and videos do, and fall back to the typed tile when the file is
// too big or cannot be drawn.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/file_message.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../file_preview/file_preview_fakes.dart';

const _svgSource =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
    '<circle cx="50" cy="50" r="40" fill="#2F6BF6"/></svg>';

PreviewFile _file(String name, {String mime = 'image/svg+xml', int size = 99}) {
  return PreviewFile(
    bucket: 'chat-files',
    path: 'conversation-1/$name',
    name: name,
    mimeType: mime,
    size: size,
    messageId: 'message-$name',
    conversationId: 'conversation-1',
    senderName: 'Ada',
    sentAt: DateTime.utc(2026, 10, 14, 9, 30),
  );
}

RenderingThumbnailService _service(FakeFileFetcher fetcher) {
  return RenderingThumbnailService(
    service: FakeFilePreviewService(),
    fetcher: fetcher,
    bridge: FakeNativeFileBridge(isSupported: false),
  );
}

void main() {
  group('the thumbnail service', () {
    test('gives the SVG source of an SVG file', () async {
      final file = _file('logo.svg');
      final bytes = await _service(
        FakeFileFetcher(contents: {file.path: _svgSource}),
      ).thumbnailFor(file);
      expect(utf8.decode(bytes!), _svgSource);
    });

    test('gives nothing for an SVG that is too big or missing', () async {
      final big = _file('big.svg');
      final tooBig =
          '${_svgSource.substring(0, _svgSource.length - 6)}'
          '<!--${'x' * maxSvgThumbnailBytes}--></svg>';
      expect(
        await _service(
          FakeFileFetcher(contents: {big.path: tooBig}),
        ).thumbnailFor(big),
        isNull,
      );
      expect(
        await _service(FakeFileFetcher()).thumbnailFor(_file('gone.svg')),
        isNull,
      );
    });

    test('remembers it, so scrolling back reads nothing again', () async {
      final file = _file('logo.svg');
      final fetcher = FakeFileFetcher(contents: {file.path: _svgSource});
      final service = _service(fetcher);
      await service.thumbnailFor(file);
      fetcher.contents = {};
      expect(utf8.decode((await service.thumbnailFor(file))!), _svgSource);
    });
  });

  group('the file card', () {
    Widget card(PreviewFile file, FakeFileFetcher fetcher) {
      return ProviderScope(
        overrides: [
          ...filePreviewOverrides(
            fetcher: fetcher,
            thumbnails: _service(fetcher),
          ),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: FileMessageContent(
                  card: true,
                  textColor: Colors.black,
                  messageId: file.messageId,
                  conversationId: file.conversationId,
                  attachment: FileAttachment(
                    bucket: file.bucket,
                    path: file.path,
                    name: file.name,
                    mimeType: file.mimeType,
                    size: file.size,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('draws an SVG file at the top', (tester) async {
      final file = _file('logo.svg');
      await tester.pumpWidget(
        card(file, FakeFileFetcher(contents: {file.path: _svgSource})),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(ValueKey('file-svg-thumbnail-${file.key}')),
        findsOneWidget,
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('logo.svg'), findsOneWidget);
    });

    testWidgets('keeps the typed tile for an SVG that cannot be read', (
      tester,
    ) async {
      final file = _file('logo.svg');
      await tester.pumpWidget(card(file, FakeFileFetcher()));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.text('SVG'), findsWidgets);
    });

    testWidgets('keeps the typed tile for a broken SVG', (tester) async {
      final file = _file('broken.svg');
      await tester.pumpWidget(
        card(file, FakeFileFetcher(contents: {file.path: 'not an svg'})),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('SVG'), findsWidgets);
    });
  });
}
