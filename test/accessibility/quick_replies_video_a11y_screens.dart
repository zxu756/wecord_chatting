// Quick replies, the away auto-reply (A8) and round video messages (A13), for
// the accessibility guard (guidelines_test.dart) and the screenshot tools: the
// settings page with its phrases, the empty page, the editor, the away sheet,
// the status sheet with its new row, the slash list in a chat, the picker from
// the "+" menu, an auto-reply in a thread, the recording page (ready,
// recording, playing back, camera refused), round videos in a thread, on the
// desktop, and the larger viewer.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/quick_replies/away_reply_sheet.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_models.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_repository.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_screen.dart';
import 'package:wecord/features/chats/video_note/video_note_camera.dart';
import 'package:wecord/features/chats/video_note/video_note_models.dart';
import 'package:wecord/features/chats/video_note/video_note_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../features/chats/quick_replies/quick_replies_fakes.dart';
import '../features/chats/video_note/video_note_fakes.dart';
import '../features/file_preview/file_preview_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

const _replies = [
  QuickReply(
    id: 'r1',
    shortcut: 'address',
    body: '12 Main Street, Auckland. Ring the bell twice.',
  ),
  QuickReply(
    id: 'r2',
    shortcut: 'pay',
    body:
        'Bank 12-3456-7890123-00. Please add your name as the reference so I '
        'can find it.',
  ),
  QuickReply(
    id: 'r3',
    shortcut: 'hours',
    body: 'Open 9 to 5, Monday to Friday',
  ),
  QuickReply(id: 'r4', shortcut: '地址', body: '朝阳路 1 号'),
];

FakeQuickRepliesRepository _quick(
  PhoneWorld world, {
  List<QuickReply> replies = _replies,
  AwayReply away = const AwayReply(),
}) {
  final repository = FakeQuickRepliesRepository(replies: replies, away: away);
  world.extraOverrides = [
    ...world.extraOverrides,
    quickRepliesRepositoryProvider.overrideWithValue(repository),
  ];
  return repository;
}

AwayReply _awayOn() => AwayReply(
  enabled: true,
  message: "I'm on a hike until Monday and will answer when I'm back.",
  until: DateTime.now().add(const Duration(days: 2)),
  duringQuietHours: true,
);

Future<void> _settings(WidgetTester tester, PhoneWorld world) async {
  _quick(world, away: _awayOn());
  await pumpStandalone(tester, world, const QuickRepliesScreen());
}

Future<void> _settingsEmpty(WidgetTester tester, PhoneWorld world) async {
  _quick(world, replies: const []);
  await pumpStandalone(tester, world, const QuickRepliesScreen());
}

Future<void> _sheetHost(WidgetTester tester, PhoneWorld world) async {
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
}

Future<void> _editor(WidgetTester tester, PhoneWorld world) async {
  _quick(world);
  await _sheetHost(tester, world);
  final context = tester.element(find.byType(Scaffold));
  unawaited(showQuickReplyEditor(context, reply: _replies[1]));
  await settle(tester);
}

Future<void> _editorTaken(WidgetTester tester, PhoneWorld world) async {
  _quick(world);
  await _sheetHost(tester, world);
  final context = tester.element(find.byType(Scaffold));
  unawaited(showQuickReplyEditor(context));
  await settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('quick-reply-shortcut')),
    'PAY',
  );
  await tester.enterText(
    find.byKey(const ValueKey('quick-reply-body')),
    'Another phrase',
  );
  await tester.tap(find.byKey(const ValueKey('quick-reply-save')));
  await settle(tester);
}

Future<void> _awaySheet(WidgetTester tester, PhoneWorld world) async {
  _quick(world, away: _awayOn());
  await _sheetHost(tester, world);
  final context = tester.element(find.byType(Scaffold));
  unawaited(showAwayReplySheet(context));
  await settle(tester);
}

Future<void> _statusSheet(WidgetTester tester, PhoneWorld world) async {
  _quick(world, away: _awayOn());
  await _sheetHost(tester, world);
  final context = tester.element(find.byType(Scaffold));
  unawaited(showCustomStatusSheet(context));
  await settle(tester);
}

Future<void> _openThread(WidgetTester tester, PhoneWorld world) async {
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

Future<void> _slashList(WidgetTester tester, PhoneWorld world) async {
  _quick(world);
  await _openThread(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('chat-composer-field')),
    '/',
  );
  await settle(tester);
}

Future<void> _picker(WidgetTester tester, PhoneWorld world) async {
  _quick(world);
  await _openThread(tester, world);
  await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('composer-quick-replies-entry')));
  await settle(tester);
}

Future<void> _autoReplyThread(WidgetTester tester, PhoneWorld world) async {
  _quick(world);
  world.chats.messages = [
    phoneMessage('m1', me, 'Are you free for a call tonight?', minutesAgo: 30),
    ChatMessage(
      id: 'm2',
      conversationId: 'dm-1',
      senderId: bart.id,
      type: MessageType.text,
      body: "I'm on a hike until Monday and will answer when I'm back.",
      createdAt: DateTime.now().subtract(const Duration(minutes: 29)),
      sender: bart,
      autoReply: true,
    ),
    phoneMessage('m3', me, 'Enjoy it!', minutesAgo: 20),
  ];
  await _openThread(tester, world);
}

// ---------------------------------------------------------------- video

/// A small picture to stand in for a round video's first frame.
class _PosterThumbnails implements ThumbnailService {
  @override
  Future<Uint8List?> thumbnailFor(PreviewFile file) async {
    final image = img.Image(width: 96, height: 96);
    for (final pixel in image) {
      final t = pixel.y / 96;
      pixel
        ..r = (60 + 120 * t).round()
        ..g = (110 + 60 * t).round()
        ..b = (150 - 40 * t).round();
    }
    return Uint8List.fromList(img.encodePng(image));
  }
}

Future<void> _recorder(
  WidgetTester tester,
  PhoneWorld world, {
  FakeVideoNoteCamera? camera,
  int steps = 0,
  bool stop = false,
}) async {
  final fake = camera ?? FakeVideoNoteCamera();
  world.extraOverrides = [
    ...world.extraOverrides,
    videoNoteCameraFactoryProvider.overrideWithValue(() => fake),
    videoControllerFactoryProvider.overrideWithValue(
      ({url, localPath}) => FakeNotePlayer(),
    ),
  ];
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
  final context = tester.element(find.byType(Scaffold));
  unawaited(showVideoNoteRecorder(context));
  await settle(tester);
  if (steps > 0 || stop) {
    await tester.tap(find.byKey(const ValueKey('video-note-record')));
    await tester.pump();
    await tester.pump(Duration(seconds: steps));
    if (stop) {
      await tester.tap(find.byKey(const ValueKey('video-note-record')));
      await settle(tester);
    }
  }
}

Future<void> _recorderReady(WidgetTester tester, PhoneWorld world) =>
    _recorder(tester, world);

Future<void> _recorderRecording(WidgetTester tester, PhoneWorld world) =>
    _recorder(tester, world, steps: 8);

Future<void> _recorderCountdown(WidgetTester tester, PhoneWorld world) =>
    _recorder(tester, world, steps: 52);

Future<void> _recorderReview(WidgetTester tester, PhoneWorld world) =>
    _recorder(tester, world, steps: 3, stop: true);

Future<void> _recorderDenied(WidgetTester tester, PhoneWorld world) =>
    _recorder(
      tester,
      world,
      camera: FakeVideoNoteCamera(
        openError: const VideoNoteCameraException(
          VideoNoteCameraProblem.denied,
        ),
      ),
    );

Map<String, dynamic> _noteAttachment(int ms) => {
  'kind': 'video',
  'bucket': 'chat-files',
  'path': 'dm-1/note-$ms.mp4',
  'name': 'video-message.mp4',
  'mime_type': 'video/mp4',
  'size': 2500000,
  'video_note': true,
  'duration_ms': ms,
};

void _videoWorld(PhoneWorld world) {
  world.filePreview = filePreviewOverrides(thumbnails: _PosterThumbnails());
  world.extraOverrides = [
    ...world.extraOverrides,
    videoControllerFactoryProvider.overrideWithValue(
      ({url, localPath}) => FakeNotePlayer(),
    ),
  ];
  world.chats.messages = [
    phoneMessage('m1', bart, 'Look what the dog did', minutesAgo: 40),
    phoneMessage(
      'm2',
      bart,
      '',
      minutesAgo: 39,
      type: MessageType.file,
      attachment: _noteAttachment(23000),
    ),
    phoneMessage('m3', me, 'Ha! Hold on, a reply', minutesAgo: 30),
    phoneMessage(
      'm4',
      me,
      '',
      minutesAgo: 29,
      type: MessageType.file,
      attachment: _noteAttachment(7000),
    ),
  ];
}

Future<void> _videoThread(WidgetTester tester, PhoneWorld world) async {
  _videoWorld(world);
  await _openThread(tester, world);
}

Future<void> _videoThreadCare(WidgetTester tester, PhoneWorld world) async {
  _care(world);
  await _videoThread(tester, world);
}

Future<void> _videoViewer(WidgetTester tester, PhoneWorld world) async {
  _videoWorld(world);
  await _openThread(tester, world);
  await tester.tap(find.byKey(const ValueKey('video-note-m2')));
  await settle(tester);
}

Future<void> _videoMenu(WidgetTester tester, PhoneWorld world) async {
  _quick(world);
  _videoWorld(world);
  world.extraOverrides = [
    ...world.extraOverrides,
    videoNoteSupportedProvider.overrideWithValue(true),
  ];
  await _openThread(tester, world);
  await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
  await settle(tester);
}

final quickRepliesVideoA11yScreens = <A11yScreen>[
  A11yScreen('quick-replies-settings', _settings),
  A11yScreen('quick-replies-empty', _settingsEmpty),
  A11yScreen('quick-reply-editor', _editor),
  A11yScreen('quick-reply-editor-taken', _editorTaken),
  A11yScreen('away-reply-sheet', _awaySheet),
  A11yScreen('custom-status-away-row', _statusSheet),
  A11yScreen('quick-reply-slash-list', _slashList),
  A11yScreen('quick-reply-picker', _picker),
  A11yScreen('auto-reply-thread', _autoReplyThread),
  A11yScreen('video-note-recorder-ready', _recorderReady),
  A11yScreen('video-note-recorder-recording', _recorderRecording),
  A11yScreen('video-note-recorder-countdown', _recorderCountdown),
  A11yScreen('video-note-recorder-review', _recorderReview),
  A11yScreen('video-note-recorder-denied', _recorderDenied),
  A11yScreen('video-note-thread', _videoThread),
  A11yScreen('video-note-thread-care', _videoThreadCare),
  A11yScreen(
    'video-note-thread-desktop',
    _videoThread,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('video-note-viewer', _videoViewer),
  A11yScreen('video-note-menu', _videoMenu),
];
