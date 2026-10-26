import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_registrations.dart';
import 'package:wecord/features/chats/video_note/video_note_bubble.dart';
import 'package:wecord/features/chats/video_note/video_note_camera.dart';
import 'package:wecord/features/chats/video_note/video_note_entry.dart';
import 'package:wecord/features/chats/video_note/video_note_models.dart';
import 'package:wecord/features/chats/video_note/video_note_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../circles/circle_detail_screen_test.dart' as circle_fakes;
import '../../file_preview/file_preview_fakes.dart';
import '../chat_thread_screen_test.dart' as chat_fakes;
import 'video_note_fakes.dart';

Map<String, dynamic> _noteJson({int ms = 12000, bool note = true}) => {
  'kind': 'video',
  'bucket': 'chat-files',
  'path': 'conversation-1/note.mp4',
  'name': 'video-message.mp4',
  'mime_type': 'video/mp4',
  'size': 2500000,
  if (note) ...{'video_note': true, 'duration_ms': ms},
};

ChatMessage _note({
  String id = 'note-1',
  int ms = 12000,
  bool viewOnce = false,
  String sender = 'user-2',
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: sender,
    type: MessageType.file,
    body: '',
    attachment: {
      ..._noteJson(ms: ms),
      if (viewOnce) 'view_once': true,
    },
    createdAt: DateTime.utc(2026, 10, 28, 9),
  );
}

void main() {
  group('the limits', () {
    VideoNoteClip clip({int ms = 10000, int size = 1000000}) {
      return VideoNoteClip(
        file: XFile.fromData(Uint8List(1), mimeType: 'video/mp4'),
        durationMs: ms,
        mimeType: 'video/mp4',
        size: size,
      );
    }

    test('a note is at most 60 seconds, at least a second, at most 30 MB', () {
      expect(maxVideoNoteSeconds, 60);
      expect(clip(ms: 999).tooShort, isTrue);
      expect(clip(ms: 1000).tooShort, isFalse);
      expect(clip(ms: 61000).tooLong, isFalse, reason: 'a second of slack');
      expect(clip(ms: 61001).tooLong, isTrue);
      expect(clip(size: maxVideoNoteBytes).tooBig, isFalse);
      expect(clip(size: maxVideoNoteBytes + 1).tooBig, isTrue);
      expect(maxVideoNoteBytes, 30 * 1024 * 1024);
    });

    test('the file name follows the type', () {
      expect(clip().fileName, 'video-message.mp4');
    });
  });

  group('the attachment', () {
    test('a video note is a video with a flag and a length', () {
      final attachment = FileAttachment.maybeFromJson(_noteJson())!;
      expect(attachment.isVideo, isTrue);
      expect(attachment.isVideoNote, isTrue);
      expect(attachment.videoNoteMs, 12000);
      expect(attachment.toJson()['kind'], 'video');
      expect(attachment.toJson()['video_note'], isTrue);
      expect(attachment.toJson()['duration_ms'], 12000);
    });

    test('an ordinary video is not one, and writes no flag', () {
      final attachment = FileAttachment.maybeFromJson(_noteJson(note: false))!;
      expect(attachment.isVideoNote, isFalse);
      expect(attachment.toJson().containsKey('video_note'), isFalse);
      expect(attachment.toJson().containsKey('duration_ms'), isFalse);
    });

    test('the flag on something that is not a video does nothing', () {
      final attachment = FileAttachment.maybeFromJson({
        'kind': 'file',
        'bucket': 'chat-files',
        'path': 'c/a.pdf',
        'name': 'a.pdf',
        'mime_type': 'application/pdf',
        'size': 10,
        'video_note': true,
        'duration_ms': 3000,
      })!;
      expect(attachment.isVideoNote, isFalse);
    });

    test('the message knows a note, but not a view-once one', () {
      expect(_note().isVideoNote, isTrue);
      expect(_note(viewOnce: true).isVideoNote, isFalse);
    });

    test('the outbox keeps the length through a restart', () {
      const media = OutboxMedia(
        kind: OutboxMediaKind.video,
        fileName: 'video-message.mp4',
        mimeType: 'video/mp4',
        size: 2500000,
        videoNoteMs: 12000,
      );
      final restored = OutboxMedia.fromJson(media.toJson());
      expect(restored.videoNoteMs, 12000);
      final json = restored.attachmentJson('conversation-1/note.mp4');
      expect(json['video_note'], isTrue);
      expect(json['duration_ms'], 12000);
      expect(json['kind'], 'video');
      expect(json['bucket'], 'chat-files');
    });

    test('an ordinary video in the outbox stays ordinary', () {
      const media = OutboxMedia(
        kind: OutboxMediaKind.video,
        fileName: 'clip.mp4',
        mimeType: 'video/mp4',
        size: 10,
      );
      expect(OutboxMedia.fromJson(media.toJson()).videoNoteMs, isNull);
      expect(
        media.attachmentJson('c/clip.mp4').containsKey('video_note'),
        isFalse,
      );
    });

    test('lengths read as minutes and seconds', () {
      expect(videoNoteLength(12000), '0:12');
      expect(videoNoteLength(60000), '1:00');
      expect(videoNoteLength(61000), '1:01');
      expect(videoNoteLength(499), '0:00');
    });
  });

  group('the recording page', () {
    late FakeVideoNoteCamera camera;
    late List<FakeNotePlayer> players;
    VideoNoteResult? sent;
    var closed = false;

    Future<void> open(
      WidgetTester tester, {
      FakeVideoNoteCamera? with_,
      bool canViewOnce = true,
    }) async {
      camera = with_ ?? FakeVideoNoteCamera();
      players = [];
      sent = null;
      closed = false;
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoNoteCameraFactoryProvider.overrideWithValue(() => camera),
            videoControllerFactoryProvider.overrideWithValue(({
              url,
              localPath,
            }) {
              final player = FakeNotePlayer();
              players.add(player);
              return player;
            }),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    sent = await showVideoNoteRecorder(
                      context,
                      canViewOnce: canViewOnce,
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> tapRecord(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('video-note-record')));
      await tester.pump();
    }

    testWidgets('opens the camera and waits for a tap', (tester) async {
      await open(tester);
      expect(camera.opened, isTrue);
      expect(find.byKey(const ValueKey('fake-camera-picture')), findsOneWidget);
      expect(
        find.text('Tap to record, or hold the button. Up to 60 seconds.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('video-note-send')), findsNothing);
      expect(camera.recording, isFalse);
    });

    testWidgets('records, shows the clock, and plays the result back', (
      tester,
    ) async {
      await open(tester);
      await tapRecord(tester);
      expect(camera.recording, isTrue);
      expect(find.text('Tap again to stop'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('video-note-clock')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('video-note-clock')))
            .data,
        '0:05',
      );

      await tapRecord(tester);
      await tester.pumpAndSettle();
      expect(camera.recording, isFalse);
      expect(find.byKey(const ValueKey('video-note-send')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-note-again')), findsOneWidget);
      expect(players, hasLength(1));
      expect(players.single.looping, isTrue);
      expect(players.single.value.isPlaying, isTrue);
    });

    testWidgets('Send hands the clip back', (tester) async {
      await open(tester);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 3));
      await tapRecord(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('video-note-send')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(sent!.clip.durationMs, 12000);
      expect(sent!.clip.mimeType, 'video/mp4');
      expect(sent!.viewOnce, isFalse);
      expect(camera.disposed, isTrue);
    });

    testWidgets('view once travels with the clip', (tester) async {
      await open(tester);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 2));
      await tapRecord(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('video-note-view-once')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('video-note-send')));
      await tester.pumpAndSettle();
      expect(sent!.viewOnce, isTrue);
    });

    testWidgets('no view-once choice where it is not offered', (tester) async {
      await open(tester, canViewOnce: false);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 2));
      await tapRecord(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-note-view-once')), findsNothing);
    });

    testWidgets('Record again goes back to the camera', (tester) async {
      await open(tester);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 2));
      await tapRecord(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('video-note-again')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-note-send')), findsNothing);
      expect(find.byKey(const ValueKey('fake-camera-picture')), findsOneWidget);
      await tapRecord(tester);
      expect(camera.starts, 2);
      expect(sent, isNull);
    });

    testWidgets('holding the button records while it is held', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('video-note-record'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(camera.recording, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(camera.recording, isFalse);
      expect(find.byKey(const ValueKey('video-note-send')), findsOneWidget);
    });

    testWidgets('it stops by itself at 60 seconds', (tester) async {
      await open(tester);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 59));
      expect(camera.recording, isTrue);
      expect(find.text('1 seconds left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(camera.recording, isFalse);
      expect(find.byKey(const ValueKey('video-note-send')), findsOneWidget);
    });

    testWidgets('the last ten seconds count down', (tester) async {
      await open(tester);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 49));
      expect(find.text('Tap again to stop'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('9 seconds left'), findsOneWidget);
    });

    testWidgets('a recording that is too short is refused with a reason', (
      tester,
    ) async {
      await open(tester, with_: FakeVideoNoteCamera(recordedMs: 400));
      await tapRecord(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tapRecord(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('That was too short. Hold a little longer.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('video-note-send')), findsNothing);
      await tapRecord(tester);
      expect(camera.starts, 2, reason: 'and it can be tried again');
    });

    testWidgets('a recording that is too big is refused', (tester) async {
      await open(
        tester,
        with_: FakeVideoNoteCamera(recordedBytes: maxVideoNoteBytes + 1),
      );
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 3));
      await tapRecord(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'That video message is too large to send. Record a shorter one.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('nothing recorded goes back to the camera', (tester) async {
      final fake = FakeVideoNoteCamera()..dropRecording = true;
      await open(tester, with_: fake);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 3));
      await tapRecord(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-note-send')), findsNothing);
      expect(find.byKey(const ValueKey('video-note-record')), findsOneWidget);
    });

    testWidgets('closing while recording throws the recording away', (
      tester,
    ) async {
      await open(tester);
      await tapRecord(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('video-note-close')));
      await tester.pumpAndSettle();
      expect(camera.cancelled, isTrue);
      expect(closed, isTrue);
      expect(sent, isNull);
      expect(camera.disposed, isTrue);
    });

    testWidgets('the camera can be switched before recording', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('video-note-switch')));
      await tester.pump();
      expect(camera.switches, 1);
      await tapRecord(tester);
      expect(
        find.byKey(const ValueKey('video-note-switch')),
        findsNothing,
        reason: 'not while recording',
      );
    });

    testWidgets('one camera has no switch', (tester) async {
      await open(tester, with_: FakeVideoNoteCamera(switchable: false));
      expect(find.byKey(const ValueKey('video-note-switch')), findsNothing);
    });

    final problems = {
      VideoNoteCameraProblem.denied: 'Camera or microphone is off',
      VideoNoteCameraProblem.missing: 'No camera found',
      VideoNoteCameraProblem.unsupported:
          "This device can't record video messages",
      VideoNoteCameraProblem.failed: 'Could not open the camera',
    };
    for (final MapEntry(key: problem, value: title) in problems.entries) {
      testWidgets('$problem is explained', (tester) async {
        await open(
          tester,
          with_: FakeVideoNoteCamera(
            openError: VideoNoteCameraException(problem),
          ),
        );
        expect(find.text(title), findsOneWidget);
        expect(find.byKey(const ValueKey('video-note-record')), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('video-note-failure-close')),
        );
        await tester.pumpAndSettle();
        expect(closed, isTrue);
      });
    }
  });

  group('in the chat', () {
    late List<FakeNotePlayer> players;

    Future<void> openChat(
      WidgetTester tester,
      List<ChatMessage> messages, {
      bool disableAnimations = false,
      bool supported = true,
      bool settle = true,
    }) async {
      players = [];
      final chats = chat_fakes.FakeChatsRepository()
        ..conversations = [
          ConversationSummary(
            id: 'conversation-1',
            type: ConversationType.direct,
            unreadCount: 0,
            title: 'Ada Lovelace',
          ),
        ]
        ..messages = messages;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...filePreviewOverrides(),
            chatsRepositoryProvider.overrideWithValue(chats),
            circlesRepositoryProvider.overrideWithValue(
              circle_fakes.FakeCirclesRepository(),
            ),
            settingsRepositoryProvider.overrideWithValue(
              chat_fakes.FakeSettingsRepository(),
            ),
            videoNoteSupportedProvider.overrideWithValue(supported),
            videoControllerFactoryProvider.overrideWithValue(({
              url,
              localPath,
            }) {
              final player = FakeNotePlayer();
              players.add(player);
              return player;
            }),
            onlineUserIdsProvider.overrideWith(
              (ref) => const Stream<Set<String>>.empty(),
            ),
            authRepositoryProvider.overrideWithValue(
              chat_fakes.FakeAuthRepository()
                ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
            ),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disableAnimations),
              child: child!,
            ),
            home: const ChatThreadScreen(conversationId: 'conversation-1'),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump();
      }
    }

    testWidgets('a note is a circle with its length, looping without sound', (
      tester,
    ) async {
      await openChat(tester, [_note()]);
      expect(find.byKey(const ValueKey('video-note-note-1')), findsOneWidget);
      expect(find.text('0:12'), findsOneWidget);
      final size = tester.getSize(
        find.byKey(const ValueKey('video-note-note-1')),
      );
      expect(size.width, size.height, reason: 'a circle');
      expect(players, hasLength(1));
      expect(players.single.lastVolume, 0);
      expect(players.single.looping, isTrue);
      expect(players.single.value.isPlaying, isTrue);
      // The message reads as one stop that names the video and its length.
      expect(
        find.bySemanticsLabel(RegExp('Video message, 0:12')),
        findsOneWidget,
      );
    });

    testWidgets('with reduced motion nothing loops', (tester) async {
      await openChat(tester, [_note()], disableAnimations: true);
      expect(find.byKey(const ValueKey('video-note-note-1')), findsOneWidget);
      expect(players, isEmpty);
    });

    testWidgets('only a few loop at once', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openChat(tester, [
        for (var i = 0; i < 5; i++) _note(id: 'note-$i'),
      ]);
      expect(players.length, maxLoopingVideoNotes);
      expect(find.byType(VideoNoteBubble), findsNWidgets(5));
    });

    testWidgets('a tap opens it larger with sound; a tap pauses', (
      tester,
    ) async {
      await openChat(tester, [_note()]);
      await tester.tap(find.byKey(const ValueKey('video-note-note-1')));
      await tester.pumpAndSettle();
      expect(find.byType(VideoNoteViewer), findsOneWidget);
      // The loop's player and the viewer's own.
      final viewer = players.last;
      expect(viewer.lastVolume, 1);
      expect(viewer.value.isPlaying, isTrue);

      await tester.tap(find.byKey(const ValueKey('video-note-viewer-picture')));
      await tester.pump();
      expect(viewer.value.isPlaying, isFalse);

      await tester.tap(find.byKey(const ValueKey('video-note-viewer-close')));
      await tester.pumpAndSettle();
      expect(find.byType(VideoNoteViewer), findsNothing);
    });

    testWidgets('a note still sending shows a spinner and cannot be opened', (
      tester,
    ) async {
      await openChat(tester, [
        _note(id: 'outbox:client-1', sender: 'user-1'),
      ], settle: false);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(players, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('video-note-outbox:client-1')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(VideoNoteViewer), findsNothing);
    });

    testWidgets('an ordinary video is still a tile, not a circle', (
      tester,
    ) async {
      await openChat(tester, [
        ChatMessage(
          id: 'video-1',
          conversationId: 'conversation-1',
          senderId: 'user-2',
          type: MessageType.file,
          body: '',
          attachment: _noteJson(note: false),
          createdAt: DateTime.utc(2026, 10, 28, 9),
        ),
      ]);
      expect(find.byType(VideoNoteBubble), findsNothing);
    });

    testWidgets('the + menu offers a video message where recording works', (
      tester,
    ) async {
      await openChat(tester, const []);
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-video-message-entry')),
        findsOneWidget,
      );
    });

    testWidgets('and not where it does not', (tester) async {
      await openChat(tester, const [], supported: false);
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-video-message-entry')),
        findsNothing,
      );
    });
  });

  group('the menu entry', () {
    test('sits after Photos and videos and before Files', () {
      expect(videoNoteComposerEntry.id, 'video-message');
      expect(videoNoteComposerEntry.order, inInclusiveRange(101, 199));
      expect(
        composerMenuExtensions.map((entry) => entry.id),
        contains('video-message'),
      );
    });
  });
}
