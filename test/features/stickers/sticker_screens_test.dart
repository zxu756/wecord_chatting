import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/stickers/add_sticker_sheet.dart';
import 'package:wecord/features/stickers/sticker_cutout.dart';
import 'package:wecord/features/stickers/sticker_formats.dart';
import 'package:wecord/features/stickers/sticker_management_screen.dart';
import 'package:wecord/features/stickers/sticker_widgets.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'sticker_fakes.dart';

Widget _app(Widget home, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: WeCordTheme.light(), home: home),
  );
}

/// Opens the add sheet on [source] from a button.
Widget _sheetHost(
  Future<Uint8List> Function() source, {
  ValueSetter<bool>? done,
}) {
  return Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final added = await showAddStickerSheet(context, source: source);
            done?.call(added);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
}

/// Lets animations run without waiting for spinners to stop.
Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _settleReal(WidgetTester tester) async {
  for (var round = 0; round < 4; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await _pump(tester);
  }
}

void main() {
  group('the personal sticker attachment', () {
    test('reads a copy in the chat folder', () {
      final attachment = StickerAttachment.maybeFromJson({
        'kind': 'sticker',
        'personal': true,
        'bucket': 'chat-images',
        'path': 'c1/sticker-1.gif',
        'mime_type': 'image/gif',
        'width': 200,
        'height': 100,
        'animated': true,
      });
      expect(attachment, isNotNull);
      expect(attachment!.isPersonal, isTrue);
      expect(attachment.personal!.bucket, 'chat-images');
      expect(attachment.personal!.path, 'c1/sticker-1.gif');
      expect(attachment.personal!.animated, isTrue);
      expect(attachment.personal!.width, 200);
    });

    test('a circle sticker still reads as before', () {
      final attachment = StickerAttachment.maybeFromJson({
        'kind': 'sticker',
        'emoji_id': 'e1',
        'name': 'wave',
        'circle_id': 'c1',
      });
      expect(attachment!.isPersonal, isFalse);
      expect(attachment.emojiId, 'e1');
    });

    test('a personal sticker without a file is nothing', () {
      expect(
        StickerAttachment.maybeFromJson({'kind': 'sticker', 'personal': true}),
        isNull,
      );
      expect(StickerAttachment.maybeFromJson({'kind': 'image'}), isNull);
    });
  });

  group('add sheet', () {
    testWidgets('previews a picture and adds it as it is', (tester) async {
      final repository = FakeUserStickersRepository();
      bool? added;
      await tester.pumpWidget(
        _app(
          _sheetHost(
            () async => sampleStickerPng(size: 200),
            done: (value) => added = value,
          ),
          stickerOverrides(repository),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);

      expect(find.text('Add to stickers'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _settleReal(tester);

      expect(added, isTrue);
      expect(repository.added.single.width, 200);
      expect(repository.added.single.animated, isFalse);
    });

    testWidgets('cut-out cuts the subject out and adds the result', (
      tester,
    ) async {
      final repository = FakeUserStickersRepository();
      final cutout = FakeStickerCutout(
        result: sampleStickerPng(size: 120, hue: 20),
      );
      await tester.pumpWidget(
        _app(
          _sheetHost(() async => samplePhotoPng()),
          stickerOverrides(repository, cutout: cutout),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);

      await tester.tap(find.byKey(const ValueKey('add-sticker-cutout-switch')));
      await _settleReal(tester);
      expect(cutout.cutOuts, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _settleReal(tester);
      // The cut-out is what was saved: 120 square, not the 512 wide photo.
      expect(repository.added.single.width, 120);
      expect(repository.added.single.height, 120);
    });

    testWidgets('turning the cut-out off adds the picture itself', (
      tester,
    ) async {
      final repository = FakeUserStickersRepository();
      final cutout = FakeStickerCutout(result: sampleStickerPng(size: 120));
      await tester.pumpWidget(
        _app(
          _sheetHost(() async => samplePhotoPng()),
          stickerOverrides(repository, cutout: cutout),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      final toggle = find.byKey(const ValueKey('add-sticker-cutout-switch'));
      await tester.tap(toggle);
      await _settleReal(tester);
      await tester.tap(toggle);
      await _settleReal(tester);
      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _settleReal(tester);
      expect(repository.added.single.width, 512);
    });

    testWidgets('a picture with no subject says so and stays as it is', (
      tester,
    ) async {
      final repository = FakeUserStickersRepository();
      final cutout = FakeStickerCutout()
        ..failure = StickerCutoutFailure.noSubject;
      await tester.pumpWidget(
        _app(
          _sheetHost(() async => samplePhotoPng()),
          stickerOverrides(repository, cutout: cutout),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      await tester.tap(find.byKey(const ValueKey('add-sticker-cutout-switch')));
      await _settleReal(tester);
      expect(
        find.text('No subject stood out in this picture.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _settleReal(tester);
      expect(repository.added.single.width, 512);
    });

    testWidgets('no cut-out switch where the device cannot', (tester) async {
      await tester.pumpWidget(
        _app(
          _sheetHost(() async => samplePhotoPng()),
          stickerOverrides(
            FakeUserStickersRepository(),
            cutout: FakeStickerCutout(available: false),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      expect(find.byKey(const ValueKey('add-sticker-save')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add-sticker-cutout-switch')),
        findsNothing,
      );
    });

    testWidgets('a GIF over 1 MB is offered as a still picture', (
      tester,
    ) async {
      final repository = FakeUserStickersRepository();
      await tester.pumpWidget(
        _app(
          _sheetHost(
            () async => tinyGif(extraBytes: maxUserStickerBytes + 100),
          ),
          stickerOverrides(repository),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      expect(
        find.byKey(const ValueKey('add-sticker-made-still')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _settleReal(tester);
      expect(repository.added.single.animated, isFalse);
    });

    testWidgets('a moving GIF within 1 MB is added moving', (tester) async {
      final repository = FakeUserStickersRepository();
      await tester.pumpWidget(
        _app(
          _sheetHost(() async => tinyGif(frames: 4)),
          stickerOverrides(repository),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      expect(
        find.byKey(const ValueKey('add-sticker-made-still')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _settleReal(tester);
      expect(repository.added.single.animated, isTrue);
      expect(repository.added.single.format, StickerFormat.gif);
    });

    testWidgets('a full library says so', (tester) async {
      final repository = FakeUserStickersRepository()
        ..addError = UserStickerException.full();
      await tester.pumpWidget(
        _app(
          _sheetHost(() async => sampleStickerPng()),
          stickerOverrides(repository),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _settleReal(tester);
      expect(
        find.text('You can keep up to 300 stickers. Delete some to add more.'),
        findsOneWidget,
      );
    });

    testWidgets('a download that fails can be tried again', (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        _app(
          _sheetHost(() async {
            attempts++;
            if (attempts == 1) {
              throw StateError('offline');
            }
            return sampleStickerPng();
          }),
          stickerOverrides(FakeUserStickersRepository()),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      expect(find.byKey(const ValueKey('add-sticker-error')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-sticker-retry')));
      await _settleReal(tester);
      expect(find.byKey(const ValueKey('add-sticker-error')), findsNothing);
      expect(find.byKey(const ValueKey('add-sticker-save')), findsOneWidget);
    });

    testWidgets('the cut-out waits while it works', (tester) async {
      final gate = Completer<void>();
      final cutout = FakeStickerCutout()..gate = gate;
      await tester.pumpWidget(
        _app(
          _sheetHost(() async => samplePhotoPng()),
          stickerOverrides(FakeUserStickersRepository(), cutout: cutout),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      await _settleReal(tester);
      await tester.tap(find.byKey(const ValueKey('add-sticker-cutout-switch')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add-sticker-cutout-switch')),
        findsNothing,
      );
      gate.complete();
      await _settleReal(tester);
      expect(
        find.byKey(const ValueKey('add-sticker-cutout-switch')),
        findsOneWidget,
      );
    });
  });

  group('reduced motion', () {
    void reduceMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }

    Future<void> pumpSticker(WidgetTester tester, {required bool animated}) {
      return tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: StickerFileImage(
                file: const StickerFile('chat-images', 'c/s.gif'),
                size: 100,
                animated: animated,
                fallback: const SizedBox(),
              ),
            ),
          ),
          stickerOverrides(FakeUserStickersRepository(), image: tinyGif()),
        ),
      );
    }

    testWidgets('an animated sticker holds on its first frame', (tester) async {
      reduceMotion(tester);
      await pumpSticker(tester, animated: true);
      await _settleReal(tester);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
      // Small enough to hold still without a play button.
      expect(find.byTooltip('Play animation'), findsNothing);
    });

    testWidgets('a still sticker is left alone', (tester) async {
      reduceMotion(tester);
      await pumpSticker(tester, animated: false);
      await _settleReal(tester);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('an animated sticker plays without reduced motion', (
      tester,
    ) async {
      await pumpSticker(tester, animated: true);
      await _settleReal(tester);
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('My stickers page', () {
    Future<FakeUserStickersRepository> open(
      WidgetTester tester, {
      List<UserSticker>? stickers,
    }) async {
      final repository = FakeUserStickersRepository(
        stickers ??
            [
              userSticker('s1', sortKey: 1),
              userSticker('s2', animated: true, sortKey: 2),
              userSticker('s3', sortKey: 3),
            ],
      );
      await tester.pumpWidget(
        _app(const StickerManagementScreen(), stickerOverrides(repository)),
      );
      await _settleReal(tester);
      return repository;
    }

    testWidgets('lists the library with a count', (tester) async {
      await open(tester);
      expect(find.text('My stickers'), findsOneWidget);
      expect(find.text('3 of 300 stickers'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-sticker-row-s1')), findsOneWidget);
      expect(find.text('Animated sticker'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes the sticker', (
      tester,
    ) async {
      final repository = await open(tester);
      await tester.tap(find.byKey(const ValueKey('my-sticker-delete-s2')));
      await _pump(tester);
      expect(find.text('Delete this sticker?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _pump(tester);
      expect(repository.deleted, isEmpty);

      await tester.tap(find.byKey(const ValueKey('my-sticker-delete-s2')));
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('sticker-delete-confirm')));
      await _settleReal(tester);
      expect(repository.deleted, ['s2']);
      expect(find.byKey(const ValueKey('my-sticker-row-s2')), findsNothing);
      expect(find.text('2 of 300 stickers'), findsOneWidget);
    });

    testWidgets('dragging a row saves the new order', (tester) async {
      final repository = await open(tester);
      final list = tester.widget<ReorderableListView>(
        find.byKey(const ValueKey('my-stickers-list')),
      );
      list.onReorderItem!(0, 2);
      await _settleReal(tester);
      expect(repository.reorders.single, ['s2', 's3', 's1']);
    });

    testWidgets('an empty library points at the message menu', (tester) async {
      await open(tester, stickers: const []);
      expect(find.byKey(const ValueKey('my-stickers-empty')), findsOneWidget);
      expect(find.textContaining('Add to stickers'), findsOneWidget);
    });
  });
}
