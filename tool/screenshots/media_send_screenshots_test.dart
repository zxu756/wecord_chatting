// Renders sending photos, videos and files: the tray above the composer,
// albums in the chat, placeholders while pictures load, uploads with
// progress rings and a failed one, and the drop overlay. Writes PNGs for
// eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/media_send_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/media-send/phone-light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=MEDIA_DESKTOP=true for the 1440x900 desktop.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/media_send/chat_drop_zone.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/chats/offline/outbox_provider.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/media-send/phone-light',
);
const _desktop = bool.fromEnvironment('MEDIA_DESKTOP');

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

/// Pictures with a sky, a sun and two hills, in different colours.
Uint8List _scene(int seed, int width, int height) {
  const palettes = [
    // sky top, sky bottom, sun, far hill, near hill
    [0x2B4C7E, 0xF2A65A, 0xFFE8A3, 0x6A5D7B, 0x2D3047],
    [0x1D3557, 0x8ECAE6, 0xFFFFFF, 0x457B9D, 0x264653],
    [0xFF8C61, 0xFFD6A5, 0xFFF1D0, 0x9B5DE5, 0x4A306D],
    [0x3A86FF, 0xBDE0FE, 0xFFFFFF, 0x2A9D8F, 0x1B4332],
    [0x6D597A, 0xE56B6F, 0xFFD89B, 0x355070, 0x1F2A44],
    [0x2A9D8F, 0xE9F5DB, 0xFFF3B0, 0x588157, 0x344E41],
    [0x14213D, 0x5C6B9A, 0xFCA311, 0x3D5A80, 0x0B132B],
    [0xE76F51, 0xF4A261, 0xFFF3C4, 0x8D5B4C, 0x4F3B33],
  ];
  final colors = palettes[seed % palettes.length];
  img.ColorRgb8 rgb(int value) =>
      img.ColorRgb8((value >> 16) & 255, (value >> 8) & 255, value & 255);
  img.ColorRgb8 mix(int a, int b, double t) {
    final x = rgb(a);
    final y = rgb(b);
    return img.ColorRgb8(
      (x.r + (y.r - x.r) * t).round(),
      (x.g + (y.g - x.g) * t).round(),
      (x.b + (y.b - x.b) * t).round(),
    );
  }

  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    img.drawLine(
      image,
      x1: 0,
      y1: y,
      x2: width - 1,
      y2: y,
      color: mix(colors[0], colors[1], y / height),
    );
  }
  img.fillCircle(
    image,
    x: (width * (0.25 + 0.5 * ((seed * 37 % 100) / 100))).round(),
    y: (height * 0.38).round(),
    radius: (math.min(width, height) * 0.13).round(),
    color: rgb(colors[2]),
  );
  for (var x = 0; x < width; x++) {
    final far = height * 0.64 + math.sin(x / width * 5 + seed) * height * 0.05;
    img.drawLine(
      image,
      x1: x,
      y1: far.round(),
      x2: x,
      y2: height - 1,
      color: rgb(colors[3]),
    );
    final near =
        height * 0.8 + math.sin(x / width * 7 + seed * 2) * height * 0.04;
    img.drawLine(
      image,
      x1: x,
      y1: near.round(),
      x2: x,
      y2: height - 1,
      color: rgb(colors[4]),
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

/// A picture that never finishes loading, so only the BlurHash shows.
class _NeverImage extends ImageProvider<_NeverImage> {
  @override
  Future<_NeverImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _NeverImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// An outbox that holds fixed entries, as if they were being sent.
class _FixedOutbox extends OutboxNotifier {
  _FixedOutbox(this.entries);

  final List<OutboxEntry> entries;

  @override
  List<OutboxEntry> build() => entries;
}

class _Sample {
  _Sample(this.name, this.seed, this.width, this.height)
    : bytes = _scene(seed, width, height);

  final String name;
  final int seed;
  final int width;
  final int height;
  final Uint8List bytes;
  String? blurhash;

  String get path => 'dm-1/$name.jpg';

  Map<String, dynamic> get attachment => ImageAttachment(
    bucket: 'chat-images',
    path: path,
    mimeType: 'image/jpeg',
    size: bytes.length,
    width: width,
    height: height,
    blurhash: blurhash,
  ).toJson();
}

void main() {
  late List<_Sample> samples;

  setUpAll(() async {
    await loadScreenshotFonts();
    samples = [
      _Sample('lake-1', 0, 1200, 900),
      _Sample('lake-2', 1, 1200, 900),
      _Sample('lake-3', 2, 900, 1200),
      _Sample('lake-4', 3, 1000, 1000),
      _Sample('hike-1', 4, 900, 1200),
      _Sample('hike-2', 5, 900, 1200),
      _Sample('wide', 6, 1500, 1000),
      _Sample('city-1', 7, 1200, 800),
      _Sample('city-2', 0, 1200, 900),
      _Sample('city-3', 1, 900, 1200),
      _Sample('city-4', 2, 1200, 800),
      _Sample('city-5', 3, 1000, 1000),
      _Sample('city-6', 4, 1200, 900),
      _Sample('city-7', 5, 900, 1200),
      _Sample('city-8', 6, 1200, 800),
      _Sample('city-9', 7, 1000, 1000),
      _Sample('poster', 2, 1280, 720),
    ];
    for (final sample in samples) {
      sample.blurhash = await photoBlurHash(sample.bytes);
    }
  });

  _Sample sample(String name) => samples.firstWhere((s) => s.name == name);

  ChatMessage imageMessage(
    String id,
    bool mine,
    _Sample picture, {
    String? group,
    String body = '',
    required int minutesAgo,
    List<MessageReaction> reactions = const [],
  }) {
    return ChatMessage(
      id: id,
      conversationId: 'dm-1',
      senderId: mine ? me.id : bart.id,
      type: MessageType.image,
      body: body,
      attachment: picture.attachment,
      attachmentGroupId: group,
      createdAt: minutesAgoTime(minutesAgo),
      sender: mine ? me : bart,
      reactions: reactions,
    );
  }

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    bool loadPictures = true,
  }) async {
    await tester.runAsync(() async {
      if (loadPictures) {
        for (final element in find.byType(Image).evaluate()) {
          final image = element.widget as Image;
          await precacheImage(
            image.image,
            element,
          ).timeout(const Duration(seconds: 3), onTimeout: () {});
        }
      }
      // BlurHash pictures decode on the engine's own time.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await settle(tester);
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

  /// Opens the direct chat with [messages] (and what else is in
  /// [overrides]).
  Future<ProviderContainer> openChat(
    WidgetTester tester,
    List<ChatMessage> messages, {
    List<Override> overrides = const [],
    bool placeholders = false,
  }) async {
    final world = PhoneWorld();
    world.chats.messages = messages;
    final byUrl = {for (final s in samples) 'https://example.com/${s.path}': s};
    world.filePreview = [
      ...world.filePreview,
      chatImageProviderFactoryProvider.overrideWithValue(
        (url) => placeholders
            ? _NeverImage()
            : MemoryImage(byUrl[url]?.bytes ?? samples.first.bytes),
      ),
      videoPosterReaderProvider.overrideWithValue(
        (file) async => sample('poster').bytes,
      ),
      ...overrides,
    ];
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(ChatThreadScreen)),
    );
  }

  void screen(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    bool loadPictures = true,
    bool desktopOnly = false,
  }) {
    if (desktopOnly && !_desktop) {
      return;
    }
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = _desktop
          ? TargetPlatform.macOS
          : TargetPlatform.iOS;
      try {
        usePhoneViewport(tester, _desktop ? _wide : _phone);
        await body(tester);
        await shoot(tester, name, loadPictures: loadPictures);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  List<ChatMessage> albumsChat() => [
    phoneMessage(
      'a0',
      bart,
      'Got the photos from the weekend 📸',
      minutesAgo: 40,
    ),
    for (var i = 0; i < 4; i++)
      imageMessage(
        'a${i + 1}',
        false,
        sample('lake-${i + 1}'),
        group: 'lake',
        body: i == 0 ? 'Saturday at the lake — the light was unreal' : '',
        minutesAgo: 38,
        reactions: i == 0
            ? const [MessageReaction(emoji: '😍', count: 2, reactedByMe: true)]
            : const [],
      ),
    for (var i = 0; i < 2; i++)
      imageMessage(
        'b${i + 1}',
        true,
        sample('hike-${i + 1}'),
        group: 'hike',
        minutesAgo: 30,
      ),
    imageMessage('c1', false, sample('wide'), minutesAgo: 20),
  ];

  screen('a1-albums', (tester) async {
    await openChat(tester, albumsChat());
  });

  screen('a2-large-albums', (tester) async {
    await openChat(tester, [
      phoneMessage('l0', bart, 'City trip dump, part 1', minutesAgo: 60),
      for (var i = 0; i < 7; i++)
        imageMessage(
          'l${i + 1}',
          false,
          sample('city-${i + 1}'),
          group: 'city7',
          body: i == 0 ? '7 from the old town' : '',
          minutesAgo: 59,
        ),
      for (var i = 0; i < 2; i++)
        imageMessage(
          'm${i + 1}',
          true,
          sample('city-${i + 8}'),
          group: 'city2',
          minutesAgo: 20,
        ),
    ]);
  });

  screen('a3-placeholders', (tester) async {
    await openChat(tester, albumsChat(), placeholders: true);
  }, loadPictures: false);

  screen('u1-uploading-and-failed', (tester) async {
    final store = MemoryPendingMediaStore();
    final uploading = [for (var i = 0; i < 4; i++) 'up-${i + 1}'];
    final failed = ['fail-1', 'fail-2'];
    OutboxEntry entry(
      String clientId,
      _Sample picture, {
      required String group,
      required int index,
      OutboxState state = OutboxState.sending,
      String caption = '',
    }) {
      return OutboxEntry(
        clientId: clientId,
        conversationId: 'dm-1',
        body: caption,
        createdAt: DateTime.now().toUtc().add(Duration(microseconds: index)),
        state: state,
        media: OutboxMedia(
          kind: OutboxMediaKind.image,
          fileName: '${picture.name}.jpg',
          mimeType: 'image/jpeg',
          size: picture.bytes.length,
          width: picture.width,
          height: picture.height,
          blurhash: picture.blurhash,
          groupId: group,
          groupIndex: index,
          hasPreview: true,
        ),
      );
    }

    final tracker = UploadProgressTracker();
    tracker.report('up-2', 0.64);
    final entries = [
      // The first picture of the album is already stored; see below.
      entry('up-2', sample('lake-2'), group: 'going', index: 1),
      entry('up-3', sample('lake-3'), group: 'going', index: 2),
      entry('up-4', sample('lake-4'), group: 'going', index: 3),
      entry(
        'fail-1',
        sample('hike-1'),
        group: 'broken',
        index: 0,
        state: OutboxState.failed,
        caption: 'Hike photos',
      ),
      entry(
        'fail-2',
        sample('hike-2'),
        group: 'broken',
        index: 1,
        state: OutboxState.failed,
      ),
    ];
    for (final item in entries) {
      final picture = samples.firstWhere(
        (s) => item.media!.fileName == '${s.name}.jpg',
      );
      unawaited(store.put(item.clientId, Stream.value(picture.bytes)));
      unawaited(store.putPreview(item.clientId, picture.bytes));
    }
    expect(uploading.length + failed.length, 6);
    await openChat(
      tester,
      [
        phoneMessage('u0', me, 'Sending you the lake ones now', minutesAgo: 4),
        imageMessage(
          'u1',
          true,
          sample('lake-1'),
          group: 'going',
          body: 'Lake day',
          minutesAgo: 3,
        ),
      ],
      overrides: [
        outboxProvider.overrideWith(() => _FixedOutbox(entries)),
        pendingMediaStoreProvider.overrideWithValue(store),
        uploadProgressTrackerProvider.overrideWithValue(tracker),
      ],
    );
  });

  /// Photos, a video and a file in the tray.
  Future<void> fillTray(
    WidgetTester tester,
    ProviderContainer container, {
    bool tooBig = false,
    bool original = false,
  }) async {
    final files = [
      for (final name in ['lake-1', 'lake-2', 'lake-3', 'hike-1'])
        XFile.fromData(
          sample(name).bytes,
          name: '$name.jpg',
          path: '$name.jpg',
          mimeType: 'image/jpeg',
          length: sample(name).bytes.length,
        ),
      XFile.fromData(
        Uint8List.fromList([0, 0, 0, 24]),
        name: 'Trail run.mp4',
        path: 'Trail run.mp4',
        mimeType: 'video/mp4',
        length: tooBig ? 74 * 1024 * 1024 : 18400000,
      ),
      XFile.fromData(
        Uint8List.fromList([37, 80, 68, 70]),
        name: 'Trip plan.pdf',
        path: 'Trip plan.pdf',
        mimeType: 'application/pdf',
        length: 352000,
      ),
    ];
    final tray = container.read(mediaTrayProvider('dm-1').notifier);
    await tester.runAsync(() => tray.add(files));
    tray.setOriginal(original);
    await tester.pump();
  }

  screen('t1-tray', (tester) async {
    final container = await openChat(tester, albumsChat());
    await fillTray(tester, container);
    container.read(mediaTrayProvider('dm-1').notifier).setCaption('');
  });

  screen('t2-tray-too-big-original', (tester) async {
    final container = await openChat(tester, albumsChat());
    await fillTray(tester, container, tooBig: true, original: true);
  });

  screen('t3-attach-menu', (tester) async {
    await openChat(tester, albumsChat());
    await tester.tap(find.byTooltip(tr('Attach')));
  });

  screen('x1-drop-overlay', (tester) async {
    await openChat(tester, albumsChat());
    final context = tester.element(find.byType(ChatThreadScreen));
    Overlay.of(context).insert(
      OverlayEntry(
        builder: (_) => const Positioned.fill(
          child: IgnorePointer(child: ChatDropOverlay()),
        ),
      ),
    );
  }, desktopOnly: true);
}

DateTime minutesAgoTime(int minutes) => minutesAgo(minutes);
