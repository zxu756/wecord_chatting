// Renders the photo editor (draw, text, mosaic, crop), the media tray with
// its Edit button, and "Copy text from picture". Writes PNGs for eyeballing.
// Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/photo_editor_screenshots_test.dart \
//     --dart-define=EDITOR_SCREENS_DIR=build/photo-editor/phone-light
//
// Add --dart-define=EDITOR_DARK=true for the dark theme and
// --dart-define=EDITOR_DESKTOP=true for the 1440x900 desktop.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_tray.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/image_text/image_text_sheet.dart';
import 'package:wecord/features/photo_editor/editor_canvas.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../test/features/image_text/image_text_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'EDITOR_SCREENS_DIR',
  defaultValue: 'build/photo-editor/phone-light',
);
const _desktop = bool.fromEnvironment('EDITOR_DESKTOP');
const _dark = bool.fromEnvironment('EDITOR_DARK');

const _phone = PhoneViewport(
  name: 'phone',
  size: Size(390, 844),
  devicePixelRatio: 2,
  topInset: 47,
  bottomInset: 34,
);
const _wide = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

/// A street scene: sky, a building, a face and a car with a number plate.
Uint8List scene() {
  const width = 1200;
  const height = 900;
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    img.drawLine(
      image,
      x1: 0,
      y1: y,
      x2: width - 1,
      y2: y,
      color: img.ColorRgb8(
        (120 + y * 0.12).round(),
        (170 + y * 0.06).round(),
        (225 - y * 0.05).round(),
      ),
    );
  }
  img.fillRect(
    image,
    x1: 0,
    y1: 640,
    x2: width,
    y2: height,
    color: img.ColorRgb8(70, 74, 86),
  );
  img.fillRect(
    image,
    x1: 70,
    y1: 150,
    x2: 460,
    y2: 640,
    color: img.ColorRgb8(205, 168, 128),
  );
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 3; col++) {
      img.fillRect(
        image,
        x1: 110 + col * 115,
        y1: 195 + row * 105,
        x2: 175 + col * 115,
        y2: 265 + row * 105,
        color: img.ColorRgb8(70, 100, 140),
      );
    }
  }
  // A person.
  img.fillRect(
    image,
    x1: 700,
    y1: 330,
    x2: 800,
    y2: 560,
    color: img.ColorRgb8(210, 90, 70),
  );
  img.fillCircle(
    image,
    x: 750,
    y: 270,
    radius: 62,
    color: img.ColorRgb8(236, 190, 150),
  );
  img.fillCircle(
    image,
    x: 728,
    y: 260,
    radius: 7,
    color: img.ColorRgb8(40, 30, 30),
  );
  img.fillCircle(
    image,
    x: 772,
    y: 260,
    radius: 7,
    color: img.ColorRgb8(40, 30, 30),
  );
  img.drawLine(
    image,
    x1: 726,
    y1: 295,
    x2: 774,
    y2: 295,
    color: img.ColorRgb8(150, 60, 60),
    thickness: 5,
  );
  // A car and its plate.
  img.fillRect(
    image,
    x1: 540,
    y1: 600,
    x2: 1120,
    y2: 780,
    color: img.ColorRgb8(60, 120, 200),
    radius: 40,
  );
  img.fillRect(
    image,
    x1: 640,
    y1: 520,
    x2: 1040,
    y2: 610,
    color: img.ColorRgb8(60, 120, 200),
    radius: 30,
  );
  img.fillRect(
    image,
    x1: 760,
    y1: 690,
    x2: 920,
    y2: 745,
    color: img.ColorRgb8(245, 245, 240),
    radius: 6,
  );
  img.drawString(
    image,
    'KX 4821',
    font: img.arial24,
    x: 774,
    y: 704,
    color: img.ColorRgb8(20, 20, 20),
  );
  img.fillCircle(
    image,
    x: 650,
    y: 790,
    radius: 55,
    color: img.ColorRgb8(30, 30, 34),
  );
  img.fillCircle(
    image,
    x: 1010,
    y: 790,
    radius: 55,
    color: img.ColorRgb8(30, 30, 34),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  late Uint8List picture;
  late EditorAssets assets;

  setUpAll(() async {
    await loadScreenshotFonts();
    picture = scene();
  });

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(
          image.image,
          element,
        ).timeout(const Duration(seconds: 3), onTimeout: () {});
      }
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void screen(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = _desktop
          ? TargetPlatform.macOS
          : TargetPlatform.iOS;
      try {
        usePhoneViewport(tester, _desktop ? _wide : _phone);
        await body(tester);
        await shoot(tester, name);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// Opens the editor on the scene, optionally with [initial] edits.
  Future<void> openEditor(
    WidgetTester tester, {
    EditorDocument? initial,
  }) async {
    final loaded = await tester.runAsync(() => EditorAssets.decode(picture));
    assets = loaded!;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _dark ? WeCordTheme.dark() : WeCordTheme.light(),
        home: PhotoEditorScreen(
          sourceBytes: picture,
          fileName: 'street.jpg',
          initial: initial,
          loadAssets: (_) async => assets,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Where a point of the picture (1200 x 900) is on screen.
  Offset onScreen(WidgetTester tester, Offset source, {Rect? region}) {
    final canvas = tester.getRect(find.byType(EditorCanvas));
    final shown = region ?? const Rect.fromLTWH(0, 0, 1200, 900);
    final scale = math.min(
      canvas.width / shown.width,
      canvas.height / shown.height,
    );
    return canvas.center + (source - shown.center) * scale;
  }

  EditorDocument marks() {
    const red = 0xFFE12F35;
    return const EditorDocument()
        .withItem(
          const PenStroke(
            points: [
              Offset(520, 470),
              Offset(560, 400),
              Offset(620, 350),
              Offset(660, 330),
              Offset(690, 300),
            ],
            color: red,
            width: 11,
          ),
        )
        .withItem(
          const PenStroke(
            points: [
              Offset(670, 310),
              Offset(690, 300),
              Offset(680, 345),
              Offset(690, 300),
              Offset(725, 322),
            ],
            color: red,
            width: 11,
          ),
        )
        .withItem(
          const PenStroke(
            points: [
              Offset(90, 700),
              Offset(200, 740),
              Offset(310, 700),
              Offset(420, 740),
            ],
            color: 0xFFFFD60A,
            width: 15,
          ),
        );
  }

  screen('01-draw', (tester) async {
    await openEditor(tester, initial: marks());
  });

  screen('02-text', (tester) async {
    final text = const TextOverlay(
      id: 1,
      text: 'Found the car!',
      color: 0xFFFFFFFF,
      center: Offset(300, 800),
      pill: true,
      rotation: -0.08,
      scale: 1.1,
    );
    final tag = const TextOverlay(
      id: 2,
      text: 'Saturday!',
      color: 0xFFFFD60A,
      center: Offset(880, 170),
      scale: 1.3,
      rotation: 0.12,
    );
    await openEditor(
      tester,
      initial: marks().withItem(text).withItem(tag),
    );
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-text')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(onScreen(tester, tag.center));
    await tester.pump(const Duration(milliseconds: 300));
  });

  screen('03-mosaic', (tester) async {
    final doc = marks()
        .withItem(
          const MosaicStroke(
            points: [Offset(750, 270), Offset(752, 272)],
            width: 190,
            kind: MosaicKind.pixelate,
          ),
        )
        .withItem(
          const MosaicStroke(
            points: [Offset(780, 718), Offset(900, 718)],
            width: 90,
            kind: MosaicKind.blur,
          ),
        );
    await openEditor(tester, initial: doc);
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-mosaic')));
    await tester.pump(const Duration(milliseconds: 300));
  });

  screen('04-crop', (tester) async {
    await openEditor(tester, initial: marks());
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-crop')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('16:9'));
    await tester.pump(const Duration(milliseconds: 300));
  });

  screen('05-text-entry', (tester) async {
    await openEditor(tester, initial: marks());
    await tester.tap(find.byKey(const ValueKey('photo-editor-tool-text')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('photo-editor-text-add')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('photo-editor-text-field')),
      'See you at 8',
    );
    await tester.pump(const Duration(milliseconds: 300));
  });

  screen('06-tray', (tester) async {
    final decoded = await tester.runAsync(() => EditorAssets.decode(picture));
    assets = decoded!;
    final container = ProviderContainer(
      overrides: [
        videoPosterReaderProvider.overrideWithValue((file) async => null),
      ],
    );
    addTearDown(container.dispose);
    XFile file(String name) {
      final bytes = scene();
      return XFile.fromData(
        bytes,
        name: name,
        path: name,
        mimeType: 'image/jpeg',
        length: bytes.length,
      );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _dark ? WeCordTheme.dark() : WeCordTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MediaTray(
                  conversationId: 'c',
                  onSend: () async {},
                  onAddMore: (_) {},
                  desktop: _desktop,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => container
          .read(mediaTrayProvider('c').notifier)
          .add([file('street-1.jpg'), file('street-2.jpg')]),
    );
    final first = container.read(mediaTrayProvider('c')).items.first;
    final photo = await tester.runAsync(
      () => renderEditedPhoto(
        assets: assets,
        document: marks(),
        fileName: 'street-1.jpg',
        maxEdge: 800,
      ),
    );
    await tester.runAsync(
      () => container
          .read(mediaTrayProvider('c').notifier)
          .applyEdit(first.id, photo: photo!, document: marks()),
    );
    await tester.pump();
  });

  /// A page with a picture on it, and "Text from picture" open over it.
  Future<void> openTextSheet(
    WidgetTester tester,
    ImageTextWorld world, {
    bool translate = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: world.overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _dark ? WeCordTheme.dark() : WeCordTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: Image.memory(picture, width: 280),
              ),
              floatingActionButton: FloatingActionButton(
                key: const ValueKey('open-text'),
                onPressed: () => showImageTextSheet(
                  context,
                  file: testPicture(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open-text')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    if (translate) {
      await tester.tap(find.byKey(const ValueKey('image-text-translate')));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  screen('07-text-from-picture', (tester) async {
    final world = ImageTextWorld()
      ..recognizer.lines = const [
        'The Corner Bakery',
        'Open daily 7:00 - 19:00',
        'Fresh bread and pastries',
        'Tel 555 0142',
      ];
    await openTextSheet(tester, world);
  });

  screen('08-text-translated', (tester) async {
    final world = ImageTextWorld(aiOn: true)
      ..recognizer.lines = const [
        'La Panadería',
        'Abierto todos los días 7:00 - 19:00',
        'Pan fresco y pasteles',
      ];
    world.ai.translated =
        'The Bakery\nOpen every day 7:00 - 19:00\nFresh bread and pastries';
    await openTextSheet(tester, world, translate: true);
  });

  screen('09-text-unavailable-on-web', (tester) async {
    final world = ImageTextWorld(supported: false);
    await openTextSheet(tester, world);
  });
}
