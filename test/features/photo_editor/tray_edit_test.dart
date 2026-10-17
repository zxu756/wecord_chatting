import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_prepare.dart';
import 'package:wecord/features/chats/media_send/media_tray.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../chats/media_send/media_fakes.dart';

const _conversation = 'conversation-1';

XFile _pdf() => XFile.fromData(
  Uint8List.fromList([1, 2, 3]),
  name: 'a.pdf',
  path: 'a.pdf',
  mimeType: 'application/pdf',
  length: 3,
);

XFile _gif() {
  // A one pixel GIF.
  final bytes = Uint8List.fromList([
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, //
    0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x21, 0xF9, 0x04, 0x01, 0x00, //
    0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, //
    0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
  ]);
  return XFile.fromData(
    bytes,
    name: 'loop.gif',
    path: 'loop.gif',
    mimeType: 'image/gif',
    length: bytes.length,
  );
}

EditedPhoto _edited({int width = 40, int height = 30}) {
  final bytes = testJpeg(width, height);
  return EditedPhoto(bytes: bytes, width: width, height: height);
}

EditorDocument _marks() => const EditorDocument().withItem(
  const PenStroke(
    points: [Offset(1, 1), Offset(9, 9)],
    color: 0xFFE12F35,
    width: 3,
  ),
);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      videoPosterReaderProvider.overrideWithValue((file) async => null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MediaTray(
              conversationId: _conversation,
              onSend: () async {},
              onAddMore: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

MediaTrayController _controller(ProviderContainer c) =>
    c.read(mediaTrayProvider(_conversation).notifier);

MediaTrayState _state(ProviderContainer c) =>
    c.read(mediaTrayProvider(_conversation));

void main() {
  group('what can be edited', () {
    testWidgets('photos can, files and GIFs cannot', (tester) async {
      final container = await _pump(tester);
      await tester.runAsync(
        () => _controller(container).add([testPhoto('a.jpg'), _pdf(), _gif()]),
      );
      final items = _state(container).items;
      expect(items[0].canEdit, isTrue);
      expect(items[1].canEdit, isFalse);
      expect(items[2].canEdit, isFalse);
      expect(items[0].isEdited, isFalse);
    });
  });

  group('putting the edited copy in the tray', () {
    testWidgets('the picture is swapped, the original is kept', (tester) async {
      final container = await _pump(tester);
      final original = testPhoto('IMG_0042.HEIC', width: 80, height: 60);
      await tester.runAsync(() => _controller(container).add([original]));
      final before = _state(container).items.single;
      final edited = _edited();

      await tester.runAsync(
        () => _controller(container).applyEdit(
          before.id,
          photo: edited,
          document: _marks(),
        ),
      );
      final after = _state(container).items.single;
      expect(after.id, before.id, reason: 'same place in the tray');
      expect(after.kind, DraftKind.image);
      expect(after.name, 'IMG_0042.jpg');
      expect(after.mimeType, 'image/jpeg');
      expect(after.size, edited.bytes.length);
      expect((after.width, after.height), (40, 30));
      expect(await after.file.readAsBytes(), edited.bytes);
      expect(after.thumbnail, isNotNull);
      // The picture as chosen is kept until it is sent.
      expect(after.source, same(original));
      expect(after.isEdited, isTrue);
      expect(after.edits, _marks());
      expect(after.canEdit, isTrue);
    });

    testWidgets('editing again still remembers the first original', (
      tester,
    ) async {
      final container = await _pump(tester);
      final original = testPhoto('a.jpg');
      await tester.runAsync(() => _controller(container).add([original]));
      final id = _state(container).items.single.id;
      await tester.runAsync(() async {
        await _controller(container).applyEdit(
          id,
          photo: _edited(),
          document: _marks(),
        );
        await _controller(container).applyEdit(
          id,
          photo: _edited(width: 50, height: 20),
          document: _marks().withItem(
            const PenStroke(
              points: [Offset(2, 2), Offset(3, 3)],
              color: 0xFF000000,
              width: 2,
            ),
          ),
        );
      });
      final after = _state(container).items.single;
      expect(after.source, same(original));
      expect((after.width, after.height), (50, 20));
      expect(after.edits!.items.length, 2);
    });

    testWidgets('only that picture changes', (tester) async {
      final container = await _pump(tester);
      await tester.runAsync(
        () => _controller(container).add([testPhoto('a.jpg'), testPhoto('b.jpg')]),
      );
      final first = _state(container).items[0];
      final second = _state(container).items[1];
      await tester.runAsync(
        () => _controller(container).applyEdit(
          second.id,
          photo: _edited(),
          document: _marks(),
        ),
      );
      final items = _state(container).items;
      expect(items[0], same(first));
      expect(items[1].isEdited, isTrue);
      expect(items.map((item) => item.id), [first.id, second.id]);
    });

    testWidgets('resetting puts the original back', (tester) async {
      final container = await _pump(tester);
      final original = testPhoto('a.jpg', width: 80, height: 60);
      await tester.runAsync(() => _controller(container).add([original]));
      final id = _state(container).items.single.id;
      await tester.runAsync(() async {
        await _controller(container).applyEdit(
          id,
          photo: _edited(),
          document: _marks(),
        );
        await _controller(container).resetEdit(id);
      });
      final after = _state(container).items.single;
      expect(after.id, id);
      expect(after.isEdited, isFalse);
      expect(after.edits, isNull);
      expect((after.width, after.height), (80, 60));
      expect(await after.file.readAsBytes(), await original.readAsBytes());
    });

    testWidgets('resetting a picture that was not edited does nothing', (
      tester,
    ) async {
      final container = await _pump(tester);
      await tester.runAsync(() => _controller(container).add([testPhoto('a.jpg')]));
      final before = _state(container).items.single;
      await tester.runAsync(() => _controller(container).resetEdit(before.id));
      expect(_state(container).items.single, same(before));
    });

    testWidgets('a picture removed meanwhile is left alone', (tester) async {
      final container = await _pump(tester);
      await tester.runAsync(() => _controller(container).add([testPhoto('a.jpg')]));
      final id = _state(container).items.single.id;
      _controller(container).remove(id);
      await tester.runAsync(
        () => _controller(container).applyEdit(
          id,
          photo: _edited(),
          document: _marks(),
        ),
      );
      expect(_state(container).items, isEmpty);
    });
  });

  group('sending an edited picture', () {
    testWidgets('goes out as the JPEG, with the edit kept as the original', (
      tester,
    ) async {
      final container = await _pump(tester);
      await tester.runAsync(
        () => _controller(container).add([testPhoto('IMG_1.HEIC')]),
      );
      final id = _state(container).items.single.id;
      final edited = _edited(width: 64, height: 48);
      await tester.runAsync(
        () => _controller(container).applyEdit(
          id,
          photo: edited,
          document: _marks(),
        ),
      );
      final queued = await tester.runAsync(
        () => prepareDrafts(_state(container).items, original: false),
      );
      final item = queued!.single;
      expect(item.fileName, 'IMG_1.jpg');
      expect(item.mimeType, 'image/jpeg');
      expect(item.width, 64);
      expect(item.height, 48);
      // "Edit and resend" brings back the edited picture.
      final kept = await item.original!().expand((chunk) => chunk).toList();
      expect(kept, edited.bytes);
    });
  });

  group('the tray', () {
    testWidgets('has an Edit button on photos only', (tester) async {
      final container = await _pump(tester);
      await tester.runAsync(
        () => _controller(container).add([testPhoto('a.jpg'), _pdf()]),
      );
      await tester.pump();
      final items = _state(container).items;
      expect(
        find.byKey(ValueKey('media-tray-edit-${items[0].id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('media-tray-edit-${items[1].id}')),
        findsNothing,
      );
      // It is announced by name.
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Edit a.jpg'),
        findsOneWidget,
      );
    });

    testWidgets('the Edit button marks a picture that was edited', (
      tester,
    ) async {
      final container = await _pump(tester);
      await tester.runAsync(() => _controller(container).add([testPhoto('a.jpg')]));
      final id = _state(container).items.single.id;
      await tester.pump();
      Color? fill() {
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey('media-tray-edit-$id')),
            matching: find.byType(Container),
          ),
        );
        return (box.decoration! as BoxDecoration).color;
      }

      final plain = fill();
      await tester.runAsync(
        () => _controller(container).applyEdit(
          id,
          photo: _edited(),
          document: _marks(),
        ),
      );
      await tester.pump();
      expect(fill(), isNot(plain));
    });

    testWidgets('tapping Edit opens the full-screen editor', (tester) async {
      final container = await _pump(tester);
      await tester.runAsync(() => _controller(container).add([testPhoto('a.jpg')]));
      final id = _state(container).items.single.id;
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('media-tray-edit-$id')));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PhotoEditorScreen), findsOneWidget);
      final screen = tester.widget<PhotoEditorScreen>(
        find.byType(PhotoEditorScreen),
      );
      // Photos are scaled for sending, so the editor works to that size.
      expect(screen.maxEdge, 2560);
      expect(screen.fileName, 'a.jpg');
    });

    testWidgets('with Original quality the editor keeps the full resolution', (
      tester,
    ) async {
      final container = await _pump(tester);
      _controller(container).setOriginal(true);
      await tester.runAsync(() => _controller(container).add([testPhoto('a.jpg')]));
      final id = _state(container).items.single.id;
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('media-tray-edit-$id')));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final screen = tester.widget<PhotoEditorScreen>(
        find.byType(PhotoEditorScreen),
      );
      expect(screen.maxEdge, editorMaxEdge);
      expect(screen.quality, 95);
    });

    testWidgets('Edit waits while photos are being prepared', (tester) async {
      final container = await _pump(tester);
      await tester.runAsync(() => _controller(container).add([testPhoto('a.jpg')]));
      final id = _state(container).items.single.id;
      _controller(container).setPreparing((0, 1));
      await tester.pump();
      final pressable = tester.widget<WeCordPressable>(
        find.byKey(ValueKey('media-tray-edit-$id')),
      );
      expect(pressable.enabled, isFalse);
    });
  });
}
