import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'file_preview_fakes.dart';

PreviewFile _file(
  String name, {
  String mime = 'application/octet-stream',
  int size = 2048,
}) {
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

/// A home page with an "open" button that opens [file] in the viewer.
Widget _host({
  required PreviewFile file,
  List<PreviewFile> gallery = const [],
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  openFilePreview(context, file: file, gallery: gallery),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String? _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('file-preview-title'))).data;

void main() {
  group('previewKindFor', () {
    test('reads the extension before a generic MIME type', () {
      PreviewKind kind(
        String name, [
        String mime = 'application/octet-stream',
      ]) => previewKindFor(name: name, mimeType: mime);
      expect(kind('photo.JPG'), PreviewKind.image);
      expect(kind('clip.mov'), PreviewKind.video);
      expect(kind('song.m4a'), PreviewKind.audio);
      expect(kind('report.pdf'), PreviewKind.pdf);
      expect(kind('notes.md'), PreviewKind.markdown);
      expect(kind('main.dart'), PreviewKind.code);
      expect(kind('Dockerfile'), PreviewKind.code);
      expect(kind('data.json'), PreviewKind.json);
      expect(kind('sheet.csv'), PreviewKind.table);
      expect(kind('sheet.tsv'), PreviewKind.table);
      expect(kind('readme.txt'), PreviewKind.text);
      expect(kind('plan.docx'), PreviewKind.office);
      expect(kind('deck.key'), PreviewKind.office);
      expect(kind('budget.numbers'), PreviewKind.office);
      expect(kind('archive.zip'), PreviewKind.other);
      expect(kind('noext', 'text/plain'), PreviewKind.text);
      expect(kind('noext', 'application/pdf'), PreviewKind.pdf);
    });

    test('the gallery holds only images and videos, in order', () {
      final a = _file('a.png'), b = _file('b.pdf'), c = _file('c.mp4');
      final result = previewGalleryFor(c, [a, b, c]);
      expect(result.items.map((f) => f.name), ['a.png', 'c.mp4']);
      expect(result.index, 1);
      expect(previewGalleryFor(b, [a, b, c]).items, [b]);
    });
  });

  group('viewer routing', () {
    testWidgets('a PDF opens in the PDF viewer from the cached download', (
      tester,
    ) async {
      final fetcher = FakeFileFetcher(
        contents: {'conversation-1/notes.pdf': ''},
      );
      final file = _file('notes.pdf', mime: 'application/pdf');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(fetcher: fetcher),
        ),
      );
      await _open(tester);

      expect(find.byType(FilePreviewScreen), findsOneWidget);
      expect(_title(tester), 'notes.pdf');
      expect(find.textContaining('Ada'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-preview')), findsOneWidget);
      expect(find.text('pdf:/cache/notes.pdf'), findsOneWidget);
      expect(fetcher.downloads, ['conversation-1/notes.pdf']);
    });

    testWidgets('on the web a PDF streams from its signed link', (
      tester,
    ) async {
      final file = _file('notes.pdf', mime: 'application/pdf');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(onDisk: false),
          ),
        ),
      );
      await _open(tester);
      expect(
        find.text('pdf:https://files.test/conversation-1/notes.pdf'),
        findsOneWidget,
      );
    });

    testWidgets('code is highlighted with line numbers', (tester) async {
      final file = _file('main.dart');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(
              contents: {
                'conversation-1/main.dart': 'void main() {\n  print(1);\n}\n',
              },
            ),
          ),
        ),
      );
      await _open(tester);
      expect(find.byKey(const ValueKey('code-preview')), findsOneWidget);
      expect(
        find.textContaining('print(1);', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('1\n2\n3\n4'), findsOneWidget);
    });

    testWidgets('Markdown is rendered', (tester) async {
      final file = _file('notes.md');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(
              contents: {'conversation-1/notes.md': '# Plan\n\n- one\n- two\n'},
            ),
          ),
        ),
      );
      await _open(tester);
      expect(find.byKey(const ValueKey('markdown-preview')), findsOneWidget);
      expect(find.text('Plan', findRichText: true), findsOneWidget);
      expect(find.text('# Plan', findRichText: true), findsNothing);
    });

    testWidgets('JSON is pretty-printed', (tester) async {
      final file = _file('data.json');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(
              contents: {'conversation-1/data.json': '{"a":1,"b":[true]}'},
            ),
          ),
        ),
      );
      await _open(tester);
      expect(find.textContaining('"a": 1', findRichText: true), findsOneWidget);
    });

    testWidgets('a CSV is a table with a header that stays put', (
      tester,
    ) async {
      final file = _file('people.csv');
      final rows = [
        'name,city,score',
        for (var i = 0; i < 80; i++) 'Person $i,"Paris, FR",$i',
      ].join('\n');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(
              contents: {'conversation-1/people.csv': rows},
            ),
          ),
        ),
      );
      await _open(tester);

      final header = find.byKey(const ValueKey('csv-header'));
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('city')),
        findsOneWidget,
      );
      expect(find.text('Paris, FR'), findsWidgets);
      final headerTop = tester.getTopLeft(header).dy;

      await tester.drag(
        find.byKey(const ValueKey('csv-body')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(find.text('Person 0'), findsNothing);
      expect(tester.getTopLeft(header).dy, headerTop);
      expect(
        find.descendant(of: header, matching: find.text('name')),
        findsOneWidget,
      );
    });

    testWidgets('long text says only the start is shown', (tester) async {
      final file = _file('big.log', size: maxTextPreviewBytes + 10);
      final fetcher = FakeFileFetcher(
        contents: {'conversation-1/big.log': 'x' * (maxTextPreviewBytes + 10)},
      );
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(fetcher: fetcher),
        ),
      );
      await _open(tester);
      expect(
        find.byKey(const ValueKey('text-preview-truncated')),
        findsOneWidget,
      );
      expect(
        find.text('Showing the first 5.0 MB. Download to view the rest.'),
        findsOneWidget,
      );
    });

    testWidgets('a video opens in the video player', (tester) async {
      final file = _file('clip.mp4', mime: 'video/mp4');
      await tester.pumpWidget(
        _host(file: file, overrides: filePreviewOverrides()),
      );
      await _open(tester);
      expect(find.byType(VideoPreview), findsOneWidget);
    });

    testWidgets('other files offer Download', (tester) async {
      final actions = FakeFileActions();
      final file = _file('backup.zip');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(actions: actions),
        ),
      );
      await _open(tester);
      expect(
        find.byKey(const ValueKey('file-preview-unavailable')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('file-preview-unavailable-download')),
      );
      await tester.pumpAndSettle();
      expect(actions.saved, ['conversation-1/backup.zip']);
      expect(find.text('Saved'), findsOneWidget);
    });
  });

  group('Office files', () {
    testWidgets(
      'on Apple platforms they open in Quick Look and close with it',
      (tester) async {
        final bridge = FakeNativeFileBridge();
        final fetcher = FakeFileFetcher(
          contents: {'conversation-1/plan.docx': ''},
        );
        final file = _file('plan.docx');
        await tester.pumpWidget(
          _host(
            file: file,
            overrides: filePreviewOverrides(bridge: bridge, fetcher: fetcher),
          ),
        );
        await _open(tester);

        expect(bridge.previewed, ['/cache/plan.docx']);
        expect(
          find.byKey(const ValueKey('quick-look-showing')),
          findsOneWidget,
        );
        expect(find.text('Opening in Quick Look…'), findsOneWidget);

        bridge.dismissed.complete();
        await tester.pumpAndSettle();
        expect(find.byType(FilePreviewScreen), findsNothing);
      },
    );

    testWidgets('the download shows its progress first', (tester) async {
      final fetcher = FakeFileFetcher(
        contents: {'conversation-1/plan.docx': ''},
      )..gate = Completer<void>();
      final file = _file('plan.docx', size: 4 * 1024 * 1024);
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            bridge: FakeNativeFileBridge(),
            fetcher: fetcher,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('file-preview-loading')),
        findsOneWidget,
      );
      expect(find.text('2.0 MB of 4.0 MB'), findsOneWidget);
      fetcher.gate!.complete();
      await tester.pump();
    });

    testWidgets('on the web they show the converted PDF', (tester) async {
      final service = FakeFilePreviewService();
      final file = _file('plan.docx');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            service: service,
            convertsOnServer: true,
          ),
        ),
      );
      await _open(tester);
      expect(service.officeRequests, ['message-plan.docx']);
      expect(
        find.text('pdf:https://files.test/previews/message-plan.docx.pdf'),
        findsOneWidget,
      );
    });

    testWidgets('without a converter the web offers the download', (
      tester,
    ) async {
      final service = FakeFilePreviewService()
        ..officeError = officePreviewExceptionFor(503, {
          'error': 'preview_not_configured',
        });
      final file = _file('plan.docx');
      await tester.pumpWidget(
        _host(
          file: file,
          overrides: filePreviewOverrides(
            service: service,
            convertsOnServer: true,
          ),
        ),
      );
      await _open(tester);
      expect(find.text("Preview isn't available here"), findsOneWidget);
      expect(
        find.byKey(const ValueKey('file-preview-unavailable-download')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fake-pdf-viewer')), findsNothing);
    });

    test('function errors map to failures', () {
      expect(
        officePreviewExceptionFor(503, null).failure,
        OfficePreviewFailure.notConfigured,
      );
      expect(
        officePreviewExceptionFor(415, {'error': 'unsupported_type'}).failure,
        OfficePreviewFailure.unsupported,
      );
      expect(
        officePreviewExceptionFor(502, {'error': 'conversion_failed'}).failure,
        OfficePreviewFailure.failed,
      );
    });
  });

  testWidgets('a failed load shows an error with Retry', (tester) async {
    final fetcher = FakeFileFetcher();
    final file = _file('notes.txt');
    await tester.pumpWidget(
      _host(
        file: file,
        overrides: filePreviewOverrides(fetcher: fetcher),
      ),
    );
    await _open(tester);
    expect(find.byKey(const ValueKey('file-preview-error')), findsOneWidget);
    expect(find.text("Couldn't load this file"), findsOneWidget);

    fetcher.contents = {'conversation-1/notes.txt': 'hello there'};
    await tester.tap(find.byKey(const ValueKey('file-preview-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file-preview-error')), findsNothing);
    expect(
      find.textContaining('hello there', findRichText: true),
      findsOneWidget,
    );
  });

  group('gallery', () {
    final photos = [
      _file('one.png', mime: 'image/png'),
      _file('report.pdf', mime: 'application/pdf'),
      _file('two.png', mime: 'image/png'),
      _file('three.mp4', mime: 'video/mp4'),
    ];

    testWidgets('arrow keys page through images and videos; Esc closes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          file: photos[0],
          gallery: photos,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(onDisk: false),
          ),
        ),
      );
      await _open(tester);
      expect(_title(tester), 'one.png');
      expect(find.textContaining('1 of 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_title(tester), 'two.png');
      expect(find.textContaining('2 of 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_title(tester), 'three.mp4');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_title(tester), 'three.mp4');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_title(tester), 'two.png');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewScreen), findsNothing);
    });

    testWidgets('swiping moves to the next image', (tester) async {
      await tester.pumpWidget(
        _host(
          file: photos[0],
          gallery: photos,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(onDisk: false),
          ),
        ),
      );
      await _open(tester);
      await tester.fling(
        find.byKey(const ValueKey('file-preview-pages')),
        const Offset(-300, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(_title(tester), 'two.png');
    });

    testWidgets('a swipe down closes it on phones', (tester) async {
      await tester.pumpWidget(
        _host(
          file: photos[0],
          gallery: photos,
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(onDisk: false),
          ),
        ),
      );
      await _open(tester);
      await tester.drag(
        find.byKey(const ValueKey('file-preview-drag-dismiss')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewScreen), findsNothing);
    });

    testWidgets('desktop opens an overlay with arrow buttons', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          file: photos[2],
          gallery: photos,
          size: const Size(1440, 900),
          overrides: filePreviewOverrides(
            fetcher: FakeFileFetcher(onDisk: false),
          ),
        ),
      );
      await _open(tester);
      expect(
        find.byKey(const ValueKey('file-preview-backdrop')),
        findsOneWidget,
      );
      expect(_title(tester), 'two.png');

      await tester.tap(find.byKey(const ValueKey('file-preview-previous')));
      await tester.pumpAndSettle();
      expect(_title(tester), 'one.png');

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewScreen), findsNothing);
    });
  });
}
