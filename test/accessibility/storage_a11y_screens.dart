// Storage management (L2: Settings -> Storage) and accessibility 2.0 (L8:
// presence shapes, the chat text size, picture descriptions, captions on
// videos), for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_models.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_tray.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/storage/disk_cache.dart';
import 'package:wecord/features/storage/storage_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/presence_status.dart';

import '../features/chats/media_send/media_fakes.dart';
import '../features/storage/storage_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _mb = 1024 * 1024;

/// A device that has been used for a while: chats, pictures and files from
/// three of them, texts, a wallpaper and an attachment still being sent.
Future<StorageWorld> _usedDevice({
  bool diskAvailable = true,
  BrowserEstimate? browser,
}) async {
  final storage = StorageWorld(
    diskAvailable: diskAvailable,
    browser: browser,
    disk: diskAvailable
        ? [
            download('plan.pdf', 38 * _mb, conversationId: 'dm-1'),
            download('trip.mov', 212 * _mb, conversationId: 'group-1'),
            download('photo.jpg', 4 * _mb, conversationId: 'conv-general'),
            download('old.bin', 900 * 1024),
            DiskEntry(
              kind: DiskKind.thumbnail,
              path: '/cache/thumb',
              bytes: 3 * _mb,
              lastUsed: DateTime.utc(2026, 10, 10),
              objectKey: 'v1:chat-files/x/trip.mov',
            ),
            DiskEntry(
              kind: DiskKind.unsent,
              path: '/support/c1',
              bytes: 6 * _mb,
              lastUsed: DateTime.utc(2026, 10, 19),
            ),
          ]
        : const [],
  );
  await cacheMessagesOf(storage.cache, 'user-1', 'dm-1', 90 * 1024);
  await cacheMessagesOf(storage.cache, 'user-1', 'group-1', 340 * 1024);
  await cacheMessagesOf(storage.cache, 'user-1', 'conv-general', 40 * 1024);
  await storage.addWallpaper(2 * _mb);
  return storage;
}

Future<void> _storage(
  WidgetTester tester,
  PhoneWorld world, {
  StorageWorld? storage,
}) async {
  final device = storage ?? await _usedDevice();
  world.extraOverrides = device.overrides;
  await pumpStandalone(tester, world, const StorageScreen());
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byKey(const ValueKey('settings-page-list')),
    const Offset(0, -150),
  );
  await tester.ensureVisible(finder);
  await settle(tester);
}

Future<void> _storageScrolled(WidgetTester tester, PhoneWorld world) async {
  await _storage(tester, world);
  await _reveal(tester, find.byKey(const ValueKey('storage-chat-dm-1')));
}

Future<void> _storageAutoClean(WidgetTester tester, PhoneWorld world) async {
  await _storage(tester, world);
  await _reveal(tester, find.byKey(StorageScreen.autoCleanKey));
}

Future<void> _storageConfirm(WidgetTester tester, PhoneWorld world) async {
  await _storage(tester, world);
  await _reveal(tester, find.byKey(const ValueKey('storage-downloads')));
  await tester.tap(find.byKey(const ValueKey('storage-downloads')));
  await settle(tester);
}

Future<void> _storageConfirmChat(WidgetTester tester, PhoneWorld world) async {
  await _storage(tester, world);
  await _reveal(tester, find.byKey(const ValueKey('storage-chat-group-1')));
  await tester.tap(find.byKey(const ValueKey('storage-chat-group-1')));
  await settle(tester);
}

Future<void> _storageEmpty(WidgetTester tester, PhoneWorld world) async {
  await _storage(tester, world, storage: StorageWorld());
}

Future<void> _storageWeb(WidgetTester tester, PhoneWorld world) async {
  await _storage(
    tester,
    world,
    storage: await _usedDevice(
      diskAvailable: false,
      browser: const BrowserEstimate(usage: 96 * _mb, quota: 4096 * _mb),
    ),
  );
}

// --- Presence shapes ---------------------------------------------------

Future<void> _presenceShapes(WidgetTester tester, PhoneWorld world) async {
  Widget row(String label, PresenceStatus? status) {
    return Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ProfileAvatar(
              name: label,
              avatarUrl: null,
              size: 56,
              presence: presenceColor(context, status),
              presenceShape: presenceShapeOf(status),
              presenceLabel: presenceLabelOf(status),
            ),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(fontSize: 17)),
          ],
        ),
      ),
    );
  }

  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Online', PresenceStatus.online),
            row('Idle', PresenceStatus.idle),
            row('Do Not Disturb', PresenceStatus.doNotDisturb),
            row('Offline', null),
          ],
        ),
      ),
    ),
  );
}

Future<void> _contactsWithPresence(
  WidgetTester tester,
  PhoneWorld world,
) async {
  world.presenceStatuses = {
    bart.id: PresenceStatus.idle,
    grace.id: PresenceStatus.doNotDisturb,
    linus.id: PresenceStatus.online,
  };
  await world.open(tester, '/contacts');
}

// --- Chat text size ---------------------------------------------------

Future<void> _settingsTextSize(WidgetTester tester, PhoneWorld world) async {
  await world.open(tester, '/me');
  await _reveal(tester, find.byKey(const ValueKey('chat-text-size-row')));
}

Future<void> _settingsTextSizeDesktop(
  WidgetTester tester,
  PhoneWorld world,
) async {
  await world.open(tester, '/me');
  await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
  await settle(tester);
}

// --- Picture descriptions ----------------------------------------------

Future<void> _altTray(
  WidgetTester tester,
  PhoneWorld world, {
  bool describeFirst = false,
  bool openSheet = false,
  int photos = 2,
}) async {
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
  final tray = container.read(mediaTrayProvider('dm-1').notifier);
  await tester.runAsync(
    () => tray.add([for (var i = 0; i < photos; i++) testPhoto('p$i.jpg')]),
  );
  await settle(tester);
  if (describeFirst) {
    tray.setAlt(
      container.read(mediaTrayProvider('dm-1')).items.first.id,
      'Two kids on a red seesaw in a park',
    );
    await settle(tester);
  }
  if (openSheet) {
    await tester.tap(find.byKey(const ValueKey('media-tray-describe')));
    await settle(tester);
  }
}

Future<void> _altMessage(WidgetTester tester, PhoneWorld world) async {
  world.chats.messages = [
    phoneMessage(
      'alt-1',
      bart,
      'Look at this one',
      minutesAgo: 8,
      type: MessageType.image,
      attachment: const {
        'kind': 'image',
        'bucket': 'chat-images',
        'path': 'dm-1/seesaw.png',
        'mime_type': 'image/png',
        'size': 1024,
        'width': 1200,
        'height': 800,
        'alt': 'Two kids on a red seesaw in a park, laughing',
      },
    ),
    phoneMessage('alt-2', me, 'Love it!', minutesAgo: 6),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

// --- Captions on videos --------------------------------------------------

class _CaptionVideo extends VideoPlayerController {
  _CaptionVideo() : super.networkUrl(Uri.parse('fake://video'));

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(minutes: 1),
      size: const Size(360, 640),
    );
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  // The real dispose would talk to a platform player that is not there.
  @override
  // ignore: must_call_super
  Future<void> dispose() async {}
}

class _CaptionMaker implements VideoCaptionMaker {
  _CaptionMaker({this.hold});

  /// The captions are not ready until this completes.
  final Completer<void>? hold;

  @override
  bool get available => true;

  @override
  Future<VideoCaptions> make(
    PreviewFile file, {
    required Future<Uri> Function() url,
    DownloadProgress? onProgress,
    FetchCancel? cancel,
  }) async {
    onProgress?.call(3, 4);
    await hold?.future;
    return VideoCaptions(
      cues: const [
        CaptionCue(
          start: Duration.zero,
          end: Duration(minutes: 1),
          text: 'Then we paint the fence on Saturday morning.',
        ),
      ],
      savedAt: DateTime.utc(2026, 10, 20),
    );
  }
}

Future<void> _videoCaptions(
  WidgetTester tester,
  PhoneWorld world, {
  bool working = false,
}) async {
  final hold = working ? Completer<void>() : null;
  world.filePreview = [
    ...world.filePreview,
    videoControllerFactoryProvider.overrideWithValue(
      ({url, localPath}) => _CaptionVideo(),
    ),
    videoCaptionMakerProvider.overrideWithValue(_CaptionMaker(hold: hold)),
    videoCaptionsPreferenceStoreProvider.overrideWithValue(
      InMemoryVideoCaptionsPreferenceStore(true),
    ),
    videoCaptionCacheProvider.overrideWithValue(InMemoryVideoCaptionCache()),
  ];
  await world.open(tester, '/home');
  final context = tester.element(find.byType(Scaffold).first);
  unawaited(
    openFilePreview(
      context,
      file: const PreviewFile(
        bucket: 'chat-files',
        path: 'conversation-1/fence.mp4',
        name: 'fence.mp4',
        mimeType: 'video/mp4',
        size: 2048,
        messageId: 'message-fence',
        conversationId: 'conversation-1',
        senderName: 'Bart the Bold',
      ),
    ),
  );
  for (var round = 0; round < 6; round++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final storageA11yScreens = <A11yScreen>[
  A11yScreen('storage', _storage),
  A11yScreen('storage-chats', _storageScrolled),
  A11yScreen('storage-auto-clean', _storageAutoClean),
  A11yScreen('storage-confirm-clear', _storageConfirm),
  A11yScreen('storage-confirm-clear-chat', _storageConfirmChat),
  A11yScreen('storage-empty', _storageEmpty),
  A11yScreen('storage-web', _storageWeb),
  A11yScreen(
    'storage-desktop',
    _storage,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('presence-shapes', _presenceShapes),
  A11yScreen('contacts-presence-shapes', _contactsWithPresence),
  A11yScreen('settings-chat-text-size', _settingsTextSize),
  A11yScreen(
    'settings-chat-text-size-desktop',
    _settingsTextSizeDesktop,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('media-tray-describe', (tester, world) => _altTray(tester, world)),
  A11yScreen(
    'media-tray-described',
    (tester, world) => _altTray(tester, world, describeFirst: true),
  ),
  A11yScreen(
    'image-alt-sheet',
    (tester, world) => _altTray(tester, world, photos: 1, openSheet: true),
  ),
  A11yScreen(
    'image-alt-sheet-several',
    (tester, world) => _altTray(tester, world, openSheet: true),
  ),
  A11yScreen('image-alt-message', _altMessage),
  A11yScreen('video-captions', _videoCaptions),
  A11yScreen(
    'video-captions-making',
    (tester, world) => _videoCaptions(tester, world, working: true),
  ),
];
