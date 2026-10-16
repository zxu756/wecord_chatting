// Renders the file viewer (image, video, PDF, CSV, code, Office) and a chat
// with file cards, with real fonts and sample files, and writes PNGs for
// eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/file_preview_screenshots_test.dart \
//     --dart-define=PREVIEW_SAMPLES=build/file-preview/samples \
//     --dart-define=PHONE_SCREENS_DIR=build/file-preview/light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=PREVIEW_DESKTOP=true for 1440x900 desktop shots. The
// samples folder needs photo.jpg, poster.jpg, license.pdf, pdf_page1.png
// and plan.docx.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/file_preview/file_actions.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/native_file_bridge.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/features/file_preview/viewers/document_preview.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/navigation/app_router.dart';

import '../../test/features/file_preview/file_preview_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/file-preview/light',
);
const _samples = String.fromEnvironment(
  'PREVIEW_SAMPLES',
  defaultValue: 'build/file-preview/samples',
);
const _desktop = bool.fromEnvironment('PREVIEW_DESKTOP');

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

const _csv = '''
Region,Quarter,Signups,Active users,Retention,Revenue (USD),Owner
"Sydney, AU",Q1,12840,9310,72.5%,184200,Ada
"Sydney, AU",Q2,14220,10480,73.7%,201950,Ada
"Melbourne, AU",Q1,9120,6640,72.8%,131400,Grace
"Melbourne, AU",Q2,10050,7390,73.5%,146010,Grace
"Auckland, NZ",Q1,4310,3020,70.1%,58300,Linus
"Auckland, NZ",Q2,4980,3560,71.5%,66120,Linus
"Singapore, SG",Q1,15120,11010,72.8%,240330,Bart
"Singapore, SG",Q2,16870,12550,74.4%,268900,Bart
"Tokyo, JP",Q1,20410,14980,73.4%,355210,Ada
"Tokyo, JP",Q2,22630,16820,74.3%,389120,Ada
"Seoul, KR",Q1,11870,8450,71.2%,171800,Grace
"Seoul, KR",Q2,13090,9480,72.4%,188420,Grace
"Taipei, TW",Q1,6890,4920,71.4%,92330,Linus
"Taipei, TW",Q2,7420,5390,72.6%,99870,Linus
"Shanghai, CN",Q1,25110,18230,72.6%,402500,Bart
"Shanghai, CN",Q2,27940,20590,73.7%,441260,Bart
"Hong Kong, HK",Q1,8020,5790,72.2%,121880,Ada
"Hong Kong, HK",Q2,8790,6450,73.4%,133940,Ada
"Bangkok, TH",Q1,5530,3880,70.2%,61210,Grace
"Bangkok, TH",Q2,6110,4370,71.5%,67930,Grace
"Jakarta, ID",Q1,7340,5040,68.7%,70120,Linus
"Jakarta, ID",Q2,8120,5690,70.1%,78640,Linus
''';

const _code = r'''
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// Signs a link to a file once and reuses it for 50 minutes,
/// so the browser's HTTP cache sees the same URL.
class SignedLinks {
  SignedLinks(this._sign, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Future<Uri> Function(String path) _sign;
  final DateTime Function() _now;
  final _cache = <String, ({Uri url, DateTime expires})>{};

  static const reuseFor = Duration(minutes: 50);

  Future<Uri> linkFor(String path) async {
    final cached = _cache[path];
    if (cached != null && cached.expires.isAfter(_now())) {
      return cached.url; // still fresh
    }
    final url = await _sign(path);
    _cache[path] = (url: url, expires: _now().add(reuseFor));
    return url;
  }
}

final signedLinksProvider = Provider<SignedLinks>((ref) {
  throw UnimplementedError('override in main()');
});
''';

/// Serves the sample files from disk, as if downloaded before.
class _SampleFetcher implements FileFetcher {
  _SampleFetcher(this.files, this.texts);

  final Map<String, String> files;
  final Map<String, String> texts;

  @override
  bool get cachesOnDisk => true;

  @override
  Future<String?> cachedPath(PreviewFile file) async => files[file.path];

  @override
  Future<String> download(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    final path = files[file.path];
    if (path == null) {
      // Stays downloading (for the progress shot).
      onProgress?.call((file.size * 0.62).round(), file.size);
      return Completer<String>().future;
    }
    return path;
  }

  @override
  Future<FileBytes> readBytes(
    PreviewFile file, {
    required Future<Uri> Function() url,
    int? maxBytes,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    final text = texts[file.path] ?? '';
    return FileBytes(Uint8List.fromList(text.codeUnits), truncated: false);
  }
}

class _SampleThumbnails implements ThumbnailService {
  _SampleThumbnails(this.pdfPage, this.poster);

  final Uint8List pdfPage;
  final Uint8List poster;

  @override
  Future<Uint8List?> thumbnailFor(PreviewFile file) async =>
      switch (file.kind) {
        PreviewKind.pdf => pdfPage,
        PreviewKind.video => poster,
        _ => null,
      };
}

/// A video that is ready and paused at 0:41 of 2:14, drawn as its poster.
class _PosterVideoPlatform extends VideoPlayerPlatform {
  _PosterVideoPlatform(this.poster);

  final Uint8List poster;
  final _events = <int, StreamController<VideoEvent>>{};
  var _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _next++;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _next++;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final controller = _events[playerId] = StreamController<VideoEvent>();
    scheduleMicrotask(() {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 2, seconds: 14),
          size: const Size(1600, 1066),
        ),
      );
    });
    return controller.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 41);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => Image.memory(poster, fit: BoxFit.cover);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Image.memory(poster, fit: BoxFit.cover);
}

PreviewFile _sample(
  String name,
  String mime,
  int size, {
  int minutes = 5,
  String sender = 'Bart',
}) {
  return PreviewFile(
    bucket: 'chat-files',
    path: 'dm-1/$name',
    name: name,
    mimeType: mime,
    size: size,
    messageId: 'msg-$name',
    conversationId: 'dm-1',
    senderName: sender,
    sentAt: minutesAgo(minutes),
  );
}

final _photo = _sample('Sonoma hills.jpg', 'image/jpeg', 812000, minutes: 12);
final _photo2 = _sample('Coastline.jpg', 'image/jpeg', 412000, minutes: 11);
final _video = _sample('Trail run.mp4', 'video/mp4', 18400000, minutes: 10);
final _pdf = _sample(
  'Software license.pdf',
  'application/pdf',
  352000,
  minutes: 9,
);
final _csvFile = _sample('Signups by region.csv', 'text/csv', 1820, minutes: 8);
final _codeFile = _sample('signed_links.dart', 'text/plain', 1104, minutes: 7);
final _docx = _sample(
  'Quarterly plan.docx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  1240000,
  minutes: 6,
);
final _xlsx = _sample(
  'Budget 2027.xlsx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  4200000,
  minutes: 4,
);
final _zip = _sample(
  'Design assets.zip',
  'application/zip',
  24800000,
  minutes: 3,
);

ChatMessage _fileMessage(PreviewFile file, {bool mine = false}) {
  return phoneMessage(
    file.messageId!,
    mine ? me : bart,
    '',
    minutesAgo: DateTime.now().difference(file.sentAt!).inMinutes,
    type: MessageType.file,
    attachment: FileAttachment(
      bucket: file.bucket,
      path: file.path,
      name: file.name,
      mimeType: file.mimeType,
      size: file.size,
    ).toJson(),
  );
}

void main() {
  late Uint8List poster;
  late Uint8List pdfPage;

  setUpAll(() async {
    await loadScreenshotFonts();
    final mono = FontLoader('JetBrains Mono')
      ..addFont(
        rootBundle.load(
          'assets/fonts/jetbrains_mono/JetBrainsMono-Variable.ttf',
        ),
      );
    await mono.load();
    // PDFium for the host, from a macOS build (flutter build macos).
    const pdfium = 'build/native_assets/macos/libpdfium.dylib';
    if (File(pdfium).existsSync()) {
      Pdfrx.pdfiumModulePath = File(pdfium).absolute.path;
    }
    Pdfrx.cacheDirectoryPath = Directory.systemTemp
        .createTempSync('pdfrx')
        .path;
    poster = File('$_samples/poster.jpg').readAsBytesSync();
    pdfPage = File('$_samples/pdf_page1.png').readAsBytesSync();
    VideoPlayerPlatform.instance = _PosterVideoPlatform(poster);
  });

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      // Let file images decode.
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(
          image.image,
          element,
        ).timeout(const Duration(seconds: 3), onTimeout: () {});
      }
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

  List<Override> previewOverrides({
    bool convertsOnServer = false,
    Map<String, String>? files,
    FakeFilePreviewService? service,
  }) {
    return [
      filePreviewServiceProvider.overrideWithValue(
        service ?? FakeFilePreviewService(),
      ),
      fileFetcherProvider.overrideWithValue(
        _SampleFetcher(
          files ??
              {
                _photo.path: '$_samples/photo.jpg',
                _photo2.path: '$_samples/coast.jpg',
                _pdf.path: '$_samples/license.pdf',
                _docx.path: '$_samples/plan.docx',
              },
          {_csvFile.path: _csv.trimLeft(), _codeFile.path: _code.trimLeft()},
        ),
      ),
      nativeFileBridgeProvider.overrideWithValue(
        FakeNativeFileBridge(isSupported: !convertsOnServer),
      ),
      thumbnailServiceProvider.overrideWithValue(
        _SampleThumbnails(pdfPage, poster),
      ),
      fileActionsProvider.overrideWithValue(
        FakeFileActions(web: convertsOnServer),
      ),
      officeConvertsOnServerProvider.overrideWithValue(convertsOnServer),
    ];
  }

  Future<BuildContext> openChat(
    WidgetTester tester,
    List<Override> extra,
  ) async {
    final world = PhoneWorld();
    world.chats.messages = [
      phoneMessage(
        't1',
        bart,
        'Sending everything for the review 👇',
        minutesAgo: 13,
      ),
      _fileMessage(_photo),
      _fileMessage(_video),
      _fileMessage(_pdf),
      _fileMessage(_csvFile, mine: true),
      _fileMessage(_codeFile, mine: true),
      _fileMessage(_docx),
      _fileMessage(_xlsx),
      _fileMessage(_zip, mine: true),
    ].reversed.toList();
    await tester.pumpWidget(
      ProviderScope(
        overrides: (world..filePreview = extra).overrides,
        child: const WeCordApp(),
      ),
    );
    await tester.pump();
    // Decode the sample photos for real before any widget asks for them
    // (file reads never finish inside the test's fake clock).
    final app = tester.element(find.byType(WeCordApp));
    await tester.runAsync(() async {
      for (final name in ['photo.jpg', 'coast.jpg']) {
        final image = FileImage(File('$_samples/$name'));
        await precacheImage(image, app);
        await precacheImage(ResizeImage(image, width: 640), app);
      }
    });
    final container = ProviderScope.containerOf(app);
    final router = container.read(appRouterProvider);
    await settle(tester);
    router.go(
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
    await settle(tester);
    return tester.element(find.byType(ChatThreadScreen));
  }

  void screen(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      if (_desktop) {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      } else {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      }
      try {
        usePhoneViewport(tester, _desktop ? _wide : _phone);
        await body(tester);
        await shoot(tester, name);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> preview(
    WidgetTester tester,
    PreviewFile file, {
    List<Override>? overrides,
    List<PreviewFile> gallery = const [],
  }) async {
    final context = await openChat(tester, overrides ?? previewOverrides());
    if (!context.mounted) {
      return;
    }
    unawaited(openFilePreview(context, file: file, gallery: gallery));
    await settle(tester);
    await settle(tester);
  }

  screen('p0-chat-file-cards', (tester) async {
    await openChat(tester, previewOverrides());
    if (!_desktop) {
      await tester.drag(
        find.byKey(const ValueKey('chat-message-list')),
        const Offset(0, 420),
      );
    }
  });

  screen('p1-image', (tester) async {
    await preview(tester, _photo, gallery: [_photo, _photo2, _video]);
  });

  screen('p2-video', (tester) async {
    await preview(tester, _video, gallery: [_photo, _photo2, _video]);
    // Pause, so the poster and controls hold still.
    await tester.tap(find.byKey(const ValueKey('video-play-pause')));
  });

  screen('p3-pdf', (tester) async {
    await preview(tester, _pdf);
    // PDFium works on its own isolate: give it real time between frames.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  screen('p4-csv', (tester) async {
    await preview(tester, _csvFile);
  });

  screen('p5-code', (tester) async {
    await preview(tester, _codeFile);
  });

  screen('p6-office-quick-look', (tester) async {
    await preview(tester, _docx);
  });

  screen('p7-office-downloading', (tester) async {
    await preview(tester, _xlsx, overrides: previewOverrides(files: const {}));
  });

  screen('p8-office-web-not-configured', (tester) async {
    final service = FakeFilePreviewService()
      ..officeError = officePreviewExceptionFor(503, {
        'error': 'preview_not_configured',
      });
    await preview(
      tester,
      _docx,
      overrides: previewOverrides(convertsOnServer: true, service: service),
    );
  });

  screen('p9-other-file', (tester) async {
    await preview(tester, _zip);
  });
}
