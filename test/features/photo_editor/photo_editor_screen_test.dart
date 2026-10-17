import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/photo_editor/editor_canvas.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'editor_fakes.dart';

/// What the editor handed back when it closed.
class _Outcome {
  var closed = false;
  PhotoEditResult? result;
}

Future<_Outcome> _open(
  WidgetTester tester, {
  EditorAssets? assets,
  EditorRenderer? renderer,
  Size size = const Size(800, 900),
  EditorDocument? initial,
  bool failToLoad = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prepared = assets ?? await makeAssets(tester, width: 300, height: 200);
  final outcome = _Outcome();
  await tester.pumpWidget(
    MaterialApp(
      theme: WeCordTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () async {
                outcome.result = await Navigator.of(context)
                    .push<PhotoEditResult>(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => PhotoEditorScreen(
                          sourceBytes: Uint8List(0),
                          fileName: 'a.jpg',
                          initial: initial,
                          loadAssets: (_) async => failToLoad ? null : prepared,
                          renderer: renderer,
                        ),
                      ),
                    );
                outcome.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  return outcome;
}

Future<void> _draw(WidgetTester tester) async {
  await tester.dragFrom(
    tester.getCenter(find.byType(EditorCanvas)),
    const Offset(120, 30),
  );
  await tester.pump();
}

bool _enabled(WidgetTester tester, String key) {
  final pressable = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(WeCordPressable),
  );
  return tester.widget<WeCordPressable>(pressable.first).enabled;
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool shift = false,
  bool control = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('has the four tools, each with a name', (tester) async {
    await _open(tester);
    for (final name in ['Draw', 'Text', 'Mosaic', 'Crop']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // Every control is announced with a label.
    for (final label in ['Cancel', 'Undo', 'Redo', 'Done']) {
      expect(
        find.bySemanticsLabel(label),
        findsWidgets,
        reason: label,
      );
    }
    expect(find.byType(EditorCanvas), findsOneWidget);
  });

  testWidgets('the pen has eight colors and three widths, all named', (
    tester,
  ) async {
    await _open(tester);
    for (final name in [
      'White',
      'Black',
      'Red',
      'Orange',
      'Yellow',
      'Green',
      'Blue',
      'Purple',
    ]) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }
    for (final name in ['Thin', 'Medium', 'Thick']) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('drawing enables undo; undo and redo work from the buttons', (
    tester,
  ) async {
    await _open(tester);
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);
    await _draw(tester);
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
    expect(_enabled(tester, 'photo-editor-redo'), isFalse);
    await tester.tap(find.byKey(const ValueKey('photo-editor-undo')));
    await tester.pump();
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);
    expect(_enabled(tester, 'photo-editor-redo'), isTrue);
    await tester.tap(find.byKey(const ValueKey('photo-editor-redo')));
    await tester.pump();
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
  });

  testWidgets('⌘Z undoes and ⇧⌘Z redoes', (tester) async {
    await _open(tester);
    await _draw(tester);
    await _draw(tester);
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyZ, meta: true);
    await _key(tester, LogicalKeyboardKey.keyZ, meta: true);
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);
    expect(_enabled(tester, 'photo-editor-redo'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyZ, meta: true, shift: true);
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyZ, meta: true, shift: true);
    expect(_enabled(tester, 'photo-editor-redo'), isFalse);
  });

  testWidgets('Ctrl+Z works too, for the web and Windows', (tester) async {
    await _open(tester);
    await _draw(tester);
    await _key(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);
    await _key(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
  });

  testWidgets('Esc closes an untouched editor at once', (tester) async {
    final outcome = await _open(tester);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(outcome.closed, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('Esc after edits asks before throwing them away', (
    tester,
  ) async {
    final outcome = await _open(tester);
    await _draw(tester);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.text('Discard your edits?'), findsOneWidget);
    expect(outcome.closed, isFalse);

    await tester.tap(find.byKey(const ValueKey('photo-editor-keep-editing')));
    await tester.pumpAndSettle();
    expect(find.text('Discard your edits?'), findsNothing);
    expect(outcome.closed, isFalse);

    await _key(tester, LogicalKeyboardKey.escape);
    await tester.tap(find.byKey(const ValueKey('photo-editor-discard')));
    await tester.pumpAndSettle();
    expect(outcome.closed, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('the close button cancels like Esc', (tester) async {
    final outcome = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-cancel')));
    await tester.pumpAndSettle();
    expect(outcome.closed, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('Done without edits hands back no new picture', (tester) async {
    var rendered = 0;
    final outcome = await _open(
      tester,
      renderer: ({
        required assets,
        required document,
        required fileName,
        required maxEdge,
        quality = 85,
      }) async {
        rendered++;
        return null;
      },
    );
    await tester.tap(find.byKey(const ValueKey('photo-editor-done')));
    await tester.pumpAndSettle();
    expect(outcome.closed, isTrue);
    expect(rendered, 0);
    expect(outcome.result!.photo, isNull);
    expect(outcome.result!.document.isUnedited, isTrue);
  });

  testWidgets('Done after edits renders the picture', (tester) async {
    EditorDocument? rendered;
    int? edge;
    final outcome = await _open(
      tester,
      renderer: ({
        required assets,
        required document,
        required fileName,
        required maxEdge,
        quality = 85,
      }) async {
        rendered = document;
        edge = maxEdge;
        return EditedPhoto(
          bytes: Uint8List.fromList([1, 2, 3]),
          width: 300,
          height: 200,
        );
      },
    );
    await _draw(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-done')));
    await tester.pumpAndSettle();
    expect(outcome.closed, isTrue);
    expect(rendered!.items.single, isA<PenStroke>());
    expect(edge, 2560);
    expect(outcome.result!.photo!.bytes, [1, 2, 3]);
    expect(outcome.result!.document.items.length, 1);
  });

  testWidgets('a failed render keeps the editor open with a message', (
    tester,
  ) async {
    final outcome = await _open(
      tester,
      renderer: ({
        required assets,
        required document,
        required fileName,
        required maxEdge,
        quality = 85,
      }) async => null,
    );
    await _draw(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-done')));
    await tester.pumpAndSettle();
    expect(outcome.closed, isFalse);
    expect(find.byKey(const ValueKey('photo-editor-save-error')), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-save-error')), findsNothing);
  });

  testWidgets('a picture that cannot be opened says so', (tester) async {
    final outcome = await _open(tester, failToLoad: true);
    expect(find.byKey(const ValueKey('photo-editor-open-error')), findsOne);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(outcome.closed, isTrue);
  });

  testWidgets('text: add, type, and edit it', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-text')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-text-add')), findsOne);
    // Nothing selected yet: the text actions wait, disabled.
    expect(_enabled(tester, 'photo-editor-text-edit'), isFalse);
    expect(_enabled(tester, 'photo-editor-text-delete'), isFalse);

    await tester.tap(find.byKey(const ValueKey('photo-editor-text-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-text-entry')), findsOne);
    await tester.enterText(
      find.byKey(const ValueKey('photo-editor-text-field')),
      'Hello',
    );
    await tester.tap(find.byKey(const ValueKey('photo-editor-text-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-text-entry')), findsNothing);
    // The text is selected: its actions work.
    for (final key in ['edit', 'larger', 'smaller', 'turn', 'delete']) {
      expect(_enabled(tester, 'photo-editor-text-$key'), isTrue, reason: key);
    }
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);

    await tester.tap(find.byKey(const ValueKey('photo-editor-text-edit')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('photo-editor-text-field')),
    );
    expect(field.controller!.text, 'Hello');

    // Delete from the toolbar.
    await tester.tap(find.byKey(const ValueKey('photo-editor-text-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-editor-text-delete')));
    await tester.pumpAndSettle();
    expect(_enabled(tester, 'photo-editor-text-edit'), isFalse);
  });

  testWidgets('Esc in the text box drops the text, not the editor', (
    tester,
  ) async {
    final outcome = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-editor-text-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('photo-editor-text-field')),
      'Nope',
    );
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('photo-editor-text-entry')), findsNothing);
    expect(outcome.closed, isFalse);
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);
  });

  testWidgets('tapping empty picture in the text tool asks for text there', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-text')));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(EditorCanvas)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-text-entry')), findsOne);
  });

  testWidgets('the mosaic tool offers pixelate, blur and brush sizes', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-mosaic')));
    await tester.pumpAndSettle();
    expect(find.text('Pixelate'), findsOne);
    expect(find.text('Blur'), findsOne);
    await tester.tap(find.text('Blur'));
    await tester.pumpAndSettle();
    await _draw(tester);
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
  });

  testWidgets('crop: ratios, rotate and reset', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-crop')));
    await tester.pumpAndSettle();
    for (final label in ['Free', '1:1', '4:3', '16:9']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);

    await tester.tap(find.text('1:1'));
    await tester.pumpAndSettle();
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);

    await tester.tap(find.byKey(const ValueKey('photo-editor-rotate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-editor-crop-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-editor-undo')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('photo-editor-undo')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('photo-editor-undo')));
    await tester.pump();
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);
  });

  testWidgets('dragging a crop corner crops', (tester) async {
    EditorDocument? rendered;
    await _open(
      tester,
      renderer: ({
        required assets,
        required document,
        required fileName,
        required maxEdge,
        quality = 85,
      }) async {
        rendered = document;
        return EditedPhoto(bytes: Uint8List(3), width: 1, height: 1);
      },
    );
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-crop')));
    await tester.pumpAndSettle();
    final canvas = tester.getRect(find.byType(EditorCanvas));
    // The 300 x 200 picture is fitted to the canvas; find its corner.
    final scale = (canvas.width / 300 < canvas.height / 200)
        ? canvas.width / 300
        : canvas.height / 200;
    final corner = canvas.center + Offset(150 * scale, 100 * scale);
    await tester.dragFrom(corner - const Offset(2, 2), const Offset(-100, -80));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('photo-editor-done')));
    await tester.pumpAndSettle();
    final crop = rendered!.crop!;
    expect(crop.left, 0);
    expect(crop.top, 0);
    expect(crop.width, lessThan(300));
    expect(crop.height, lessThan(200));
  });

  testWidgets('the controls can all be reached with the keyboard', (
    tester,
  ) async {
    await _open(tester);
    await _draw(tester);
    final wanted = {
      'photo-editor-cancel',
      'photo-editor-undo',
      'photo-editor-done',
      'photo-editor-tool-draw',
      'photo-editor-tool-text',
      'photo-editor-tool-mosaic',
      'photo-editor-tool-crop',
      'photo-editor-color-ffe12f35',
      'photo-editor-width-medium',
    };
    final reached = <String>{};
    for (var i = 0; i < 60 && reached.length < wanted.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      final context = focus?.context;
      if (context == null) continue;
      context.visitAncestorElements((element) {
        final key = element.widget.key;
        if (key is ValueKey<String> && wanted.contains(key.value)) {
          reached.add(key.value);
          return false;
        }
        return true;
      });
    }
    expect(reached, wanted);
  });

  testWidgets('choosing a tool shows its options', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-crop')));
    await tester.pumpAndSettle();
    expect(find.text('16:9'), findsOneWidget);
  });

  testWidgets('works on a desktop-sized window', (tester) async {
    await _open(tester, size: const Size(1280, 800));
    expect(find.byType(EditorCanvas), findsOneWidget);
    await _draw(tester);
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
  });

  testWidgets('opens again where the edits were left', (tester) async {
    await _open(
      tester,
      initial: const EditorDocument(quarterTurns: 1).withItem(
        const PenStroke(
          points: [Offset(1, 1), Offset(20, 20)],
          color: 0xFFE12F35,
          width: 4,
        ),
      ),
    );
    // Starting edits are not undoable steps.
    expect(_enabled(tester, 'photo-editor-undo'), isFalse);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-crop')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Widget>(find.byKey(const ValueKey('photo-editor-crop-reset'))),
      isNotNull,
    );
  });

  testWidgets('a mouse wheel with ⌘ zooms and Fit to screen undoes it', (
    tester,
  ) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('photo-editor-zoom-reset')), findsNothing);
    final center = tester.getCenter(find.byType(EditorCanvas));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendEventToBinding(mouse.hover(center));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -300)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-zoom-reset')), findsOne);
    await tester.tap(find.byKey(const ValueKey('photo-editor-zoom-reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-zoom-reset')), findsNothing);
  });

  testWidgets('a trackpad pinch in the browser zooms', (tester) async {
    await _open(tester);
    final center = tester.getCenter(find.byType(EditorCanvas));
    await tester.sendEventToBinding(PointerScaleEvent(position: center, scale: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-zoom-reset')), findsOne);
  });

  testWidgets('a mouse can draw', (tester) async {
    await _open(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(EditorCanvas)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 10));
    await gesture.moveBy(const Offset(40, 10));
    await gesture.up();
    await tester.pump();
    expect(_enabled(tester, 'photo-editor-undo'), isTrue);
  });

  testWidgets('a two-finger pinch zooms instead of drawing', (tester) async {
    await _open(tester);
    final center = tester.getCenter(find.byType(EditorCanvas));
    final a = await tester.startGesture(center - const Offset(20, 0));
    final b = await tester.startGesture(center + const Offset(20, 0));
    await a.moveBy(const Offset(-60, 0));
    await b.moveBy(const Offset(60, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-editor-zoom-reset')), findsOne);
  });
}
