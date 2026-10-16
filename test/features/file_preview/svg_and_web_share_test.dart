import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/file_preview/file_actions.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'file_preview_fakes.dart';

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

Widget _host(PreviewFile file, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
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
  );
}

void main() {
  group('SVG', () {
    test('is its own preview kind', () {
      expect(
        previewKindFor(name: 'logo.svg', mimeType: 'application/octet-stream'),
        PreviewKind.svg,
      );
      expect(
        previewKindFor(name: 'logo', mimeType: 'image/svg+xml'),
        PreviewKind.svg,
      );
      expect(PreviewKind.svg.isGalleryMedia, isFalse);
      expect(PreviewKind.svg.isTextLike, isFalse);
      expect(previewIconFor(_file('logo.svg')), Icons.image_outlined);
    });

    testWidgets('is drawn as a zoomable image', (tester) async {
      final file = _file('logo.svg');
      await tester.pumpWidget(
        _host(
          file,
          filePreviewOverrides(
            fetcher: FakeFileFetcher(contents: {file.path: _svgSource}),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.ancestor(
          of: find.byType(SvgPicture),
          matching: find.byType(InteractiveViewer),
        ),
      );
      expect(viewer.maxScale, greaterThan(1));
      final matrix = viewer.transformationController!;
      expect(matrix.value.getMaxScaleOnAxis(), 1);

      // Double tap zooms in.
      final center = tester.getCenter(find.byType(SvgPicture));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(matrix.value.getMaxScaleOnAxis(), greaterThan(1.5));
      // Not shown as XML code any more.
      expect(find.textContaining('<svg'), findsNothing);
    });

    testWidgets('a broken download offers Retry', (tester) async {
      final file = _file('logo.svg');
      await tester.pumpWidget(_host(file, filePreviewOverrides()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byKey(const ValueKey('file-preview-retry')), findsOneWidget);
    });
  });

  group('Share on the web', () {
    PlatformFileActions actions({
      required FakeWebShare webShare,
      FakeFileFetcher? fetcher,
    }) => PlatformFileActions(
      service: FakeFilePreviewService(),
      fetcher: fetcher ?? FakeFileFetcher(),
      bridge: FakeNativeFileBridge(isSupported: false),
      webShare: webShare,
      isWeb: true,
    );

    test('is offered only where the browser can share', () {
      expect(actions(webShare: FakeWebShare()).canShare, isTrue);
      expect(
        actions(webShare: FakeWebShare(isAvailable: false)).canShare,
        isFalse,
      );
      expect(actions(webShare: FakeWebShare()).canOpenIn, isFalse);
    });

    test('shares the file itself when it is small', () async {
      final webShare = FakeWebShare();
      final file = _file('notes.txt', mime: 'text/plain', size: 5);
      await actions(
        webShare: webShare,
        fetcher: FakeFileFetcher(contents: {file.path: 'hello'}),
      ).share(file);
      expect(webShare.shares, hasLength(1));
      final shared = webShare.shares.single;
      expect(shared.name, 'notes.txt');
      expect(shared.mimeType, 'text/plain');
      expect(String.fromCharCodes(shared.bytes!), 'hello');
      expect(shared.url.toString(), 'https://files.test/${file.path}');
    });

    test('shares a link for big files or when fetching fails', () async {
      final webShare = FakeWebShare();
      final big = _file(
        'movie.mp4',
        mime: 'video/mp4',
        size: maxWebShareFileBytes + 1,
      );
      final broken = _file('broken.pdf', mime: 'application/pdf');
      final shareActions = actions(webShare: webShare);
      await shareActions.share(big);
      await shareActions.share(broken);
      expect(webShare.shares.map((share) => share.bytes), [null, null]);
      expect(webShare.shares.map((share) => share.url.toString()), [
        'https://files.test/${big.path}',
        'https://files.test/${broken.path}',
      ]);
    });

    testWidgets('the viewer shows Share next to Download', (tester) async {
      final fileActions = FakeFileActions(web: true, webShare: true);
      final file = _file('backup.zip', mime: 'application/zip');
      await tester.pumpWidget(
        _host(file, filePreviewOverrides(actions: fileActions)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Download'), findsOneWidget);
      expect(find.byTooltip('Open in…'), findsNothing);
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(fileActions.shared, [file.path]);
    });

    testWidgets('without the Web Share API only Download', (tester) async {
      final file = _file('backup.zip', mime: 'application/zip');
      await tester.pumpWidget(
        _host(file, filePreviewOverrides(actions: FakeFileActions(web: true))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Download'), findsOneWidget);
      expect(find.byTooltip('Share'), findsNothing);
    });
  });
}
