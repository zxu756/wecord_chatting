// Under reduced motion, animated pictures (GIF) hold on their first frame
// with a play button: avatars, the full-screen image viewer. (Album tiles
// are covered in chat_thread_screen_test.dart.)
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../features/chats/emoji_fixtures.dart';
import '../features/file_preview/file_preview_fakes.dart';

/// A GIF-named picture on disk the image providers can really read.
File _gifOnDisk() {
  final directory = Directory.systemTemp.createTempSync('wecord_gif_');
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/party.gif')..writeAsBytesSync(partyParrotPng);
}

Future<void> _decode(WidgetTester tester) async {
  // Reading the file and decoding it take real time, and their results
  // reach the widgets on the next frames.
  for (var round = 0; round < 6; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: WeCordTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

class _DiskFetcher extends FakeFileFetcher {
  _DiskFetcher(this.path);

  final String path;

  @override
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async => path;
}

void main() {
  test('only names that can move count as animated', () {
    expect(
      imageProviderAnimates(NetworkImage('https://x.test/a.gif?x=1')),
      isTrue,
    );
    expect(
      imageProviderAnimates(NetworkImage('https://x.test/a.APNG')),
      isTrue,
    );
    expect(
      imageProviderAnimates(NetworkImage('https://x.test/a.jpg')),
      isFalse,
    );
    expect(
      imageProviderAnimates(
        ResizeImage(NetworkImage('https://x.test/a.gif'), width: 64),
      ),
      isTrue,
    );
    expect(imageProviderAnimates(MemoryImage(partyParrotPng)), isFalse);
  });

  group('avatars', () {
    final makers = <String, Widget Function(ImageProvider, double)>{
      'person': (image, size) =>
          PersonAvatar(name: 'Ada', image: image, size: size),
      'thing': (image, size) =>
          ThingAvatar(label: 'Bay Area', image: image, size: size),
    };
    for (final MapEntry(key: name, value: make) in makers.entries) {
      testWidgets('a $name avatar holds a GIF under reduced motion', (
        tester,
      ) async {
        _reduceMotion(tester);
        final file = _gifOnDisk();
        await tester.pumpWidget(_app(make(FileImage(file), 96)));
        await _decode(tester);

        // The first frame, under a play button; a tap lets it play.
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byTooltip('Play animation'), findsOneWidget);
        await tester.tap(find.byTooltip('Play animation'));
        await tester.pump();
        expect(find.byTooltip('Play animation'), findsNothing);
      });

      testWidgets('a small $name avatar holds still without a button', (
        tester,
      ) async {
        _reduceMotion(tester);
        final file = _gifOnDisk();
        await tester.pumpWidget(_app(make(FileImage(file), 40)));
        await _decode(tester);

        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byTooltip('Play animation'), findsNothing);
      });

      testWidgets('a $name avatar plays a GIF without reduced motion', (
        tester,
      ) async {
        final file = _gifOnDisk();
        await tester.pumpWidget(_app(make(FileImage(file), 96)));
        await _decode(tester);

        expect(find.byType(RawImage), findsNothing);
        expect(find.byTooltip('Play animation'), findsNothing);
      });
    }

    testWidgets('a still picture is left alone under reduced motion', (
      tester,
    ) async {
      _reduceMotion(tester);
      await tester.pumpWidget(
        _app(PersonAvatar(name: 'Ada', image: MemoryImage(partyParrotPng))),
      );
      await _decode(tester);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byTooltip('Play animation'), findsNothing);
    });
  });

  group('the full-screen image viewer', () {
    Future<void> openViewer(WidgetTester tester, String name) async {
      final gif = _gifOnDisk();
      final file = PreviewFile(
        bucket: 'chat-images',
        path: 'conversation-1/$name',
        name: name,
        mimeType: name.endsWith('.gif') ? 'image/gif' : 'image/png',
        size: 2048,
        messageId: 'message-1',
        conversationId: 'conversation-1',
        senderName: 'Ada',
        sentAt: DateTime.utc(2026, 10, 14, 9, 30),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: filePreviewOverrides(fetcher: _DiskFetcher(gif.path)),
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    openFilePreview(context, file: file, gallery: [file]),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _decode(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('holds a GIF on its first frame with a play button', (
      tester,
    ) async {
      _reduceMotion(tester);
      await openViewer(tester, 'party.gif');
      expect(find.byType(FilePreviewScreen), findsOneWidget);
      expect(find.byTooltip('Play animation'), findsOneWidget);
      await tester.tap(find.byTooltip('Play animation'));
      // The viewer waits out a double tap before it takes a tap.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Play animation'), findsNothing);
    });

    testWidgets('plays a GIF as usual without reduced motion', (tester) async {
      await openViewer(tester, 'party.gif');
      expect(find.byTooltip('Play animation'), findsNothing);
    });

    testWidgets('a PNG is shown as usual under reduced motion', (tester) async {
      _reduceMotion(tester);
      await openViewer(tester, 'party.png');
      expect(find.byTooltip('Play animation'), findsNothing);
    });
  });
}
