// The photo editor, the media tray with its Edit buttons, and "Text from
// picture", for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_tray.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/image_text/image_text_sheet.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_session.dart' show EditorTool;
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';

import '../features/chats/media_send/media_fakes.dart';
import '../features/image_text/image_text_fakes.dart';
import '../features/photo_editor/editor_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

EditorDocument _marks() {
  return const EditorDocument()
      .withItem(
        const PenStroke(
          points: [Offset(20, 120), Offset(60, 90), Offset(120, 110)],
          color: 0xFFE12F35,
          width: 8,
        ),
      )
      .withItem(
        const TextOverlay(
          id: 1,
          text: 'Found it',
          color: 0xFFFFFFFF,
          center: Offset(150, 60),
          pill: true,
        ),
      )
      .withItem(
        const MosaicStroke(
          points: [Offset(200, 120), Offset(240, 125)],
          width: 40,
          kind: MosaicKind.pixelate,
        ),
      );
}

Future<void> _editor(
  WidgetTester tester,
  PhoneWorld world, {
  EditorTool? tool,
  EditorDocument? initial,
}) async {
  final assets = await makeAssets(tester, width: 320, height: 200);
  await pumpStandalone(
    tester,
    world,
    PhotoEditorScreen(
      sourceBytes: Uint8List(0),
      fileName: 'street.jpg',
      initial: initial ?? _marks(),
      loadAssets: (_) async => assets,
    ),
  );
  await settle(tester);
  if (tool != null) {
    await tester.tap(find.byKey(ValueKey('photo-editor-tool-${tool.name}')));
    await settle(tester);
  }
}

Future<void> _tray(WidgetTester tester, PhoneWorld world) async {
  final container = ProviderContainer(
    overrides: [
      videoPosterReaderProvider.overrideWithValue((file) async => null),
    ],
  );
  addTearDown(container.dispose);
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: UncontrolledProviderScope(
            container: container,
            child: MediaTray(
              conversationId: 'dm-1',
              onSend: () async {},
              onAddMore: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => container
        .read(mediaTrayProvider('dm-1').notifier)
        .add([testPhoto('a.jpg'), testPhoto('b.jpg')]),
  );
  await settle(tester);
}

Future<void> _textSheet(
  WidgetTester tester,
  PhoneWorld world, {
  required bool supported,
  bool ai = false,
}) async {
  final images = ImageTextWorld(supported: supported, aiOn: ai);
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('open-image-text'),
            onPressed: () =>
                showImageTextSheet(context, file: testPicture()),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    extraOverrides: images.overrides,
  );
  await tester.tap(find.byKey(const ValueKey('open-image-text')));
  await settle(tester);
}

final photoEditorA11yScreens = <A11yScreen>[
  A11yScreen('photo-editor-draw', (tester, world) => _editor(tester, world)),
  A11yScreen(
    'photo-editor-text',
    (tester, world) => _editor(tester, world, tool: EditorTool.text),
  ),
  A11yScreen(
    'photo-editor-mosaic',
    (tester, world) => _editor(tester, world, tool: EditorTool.mosaic),
  ),
  A11yScreen(
    'photo-editor-crop',
    (tester, world) => _editor(tester, world, tool: EditorTool.crop),
  ),
  A11yScreen(
    'photo-editor-desktop',
    (tester, world) => _editor(tester, world),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('media-tray-edit', _tray),
  A11yScreen(
    'text-from-picture',
    (tester, world) => _textSheet(tester, world, supported: true, ai: true),
  ),
  A11yScreen(
    'text-from-picture-unavailable',
    (tester, world) => _textSheet(tester, world, supported: false),
  ),
];
