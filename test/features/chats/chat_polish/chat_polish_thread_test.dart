import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_polish/chat_polish_settings.dart';
import 'package:wecord/features/chats/chat_polish/silent_send.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart' show WeCordPressable;

import '../chat_thread_screen_test.dart' as chat_fakes;

ChatMessage _message(
  String id,
  String body, {
  String senderId = 'user-2',
  ReplyPreview? replyPreview,
  bool silent = false,
  DateTime? recalledAt,
  int minute = 0,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.text,
    body: body,
    createdAt: DateTime.utc(2026, 5, 18, 4, minute),
    replyPreview: replyPreview,
    replyToMessageId: replyPreview?.messageId,
    silent: silent,
    recalledAt: recalledAt,
  );
}

class _SilentChats extends chat_fakes.FakeChatsRepository
    implements SilentMessageSender {
  final silentSends =
      <({String body, String? replyTo, ReplyPreview? preview})>[];

  @override
  Future<String?> sendSilentTextMessage({
    required String conversationId,
    required String clientId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {
    if (sendError case final error?) {
      throw error;
    }
    silentSends.add((
      body: body,
      replyTo: replyToMessageId,
      preview: replyPreview,
    ));
    return 'silent-${silentSends.length}';
  }
}

class _PausableRecorder extends chat_fakes.FakeVoiceMessageRecorder
    implements PausableVoiceRecorder {
  _PausableRecorder(this.wav);

  final Uint8List wav;
  var _paused = false;

  @override
  bool get isPaused => _paused;

  @override
  Future<void> pause() async => _paused = true;

  @override
  Future<void> resume() async => _paused = false;

  @override
  RecordedVoiceMessage? snapshot() =>
      RecordedVoiceMessage(bytes: wav, mimeType: 'audio/wav', durationMs: 4000);
}

/// A mono 1000 Hz sample rate, 16-bit WAV of [ms] milliseconds (so a sample
/// is a millisecond and the numbers are easy to read).
Uint8List _wav(int ms) {
  final data = Uint8List(ms * 2);
  final view = ByteData.sublistView(data);
  for (var i = 0; i < ms; i++) {
    view.setInt16(i * 2, (i % 100) * 300, Endian.little);
  }
  final out = Uint8List(44 + data.length);
  final header = ByteData.sublistView(out);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      out[at + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 1000, Endian.little);
  header.setUint32(28, 2000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  out.setRange(44, out.length, data);
  return out;
}

Widget _app(
  chat_fakes.FakeChatsRepository chats, {
  VoiceMessageRecorder? recorder,
}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(chats),
      voiceMessageRecorderProvider.overrideWithValue(
        recorder ?? chat_fakes.FakeVoiceMessageRecorder(),
      ),
      chatPolishStoreProvider.overrideWithValue(InMemoryChatPolishStore()),
      settingsRepositoryProvider.overrideWithValue(
        chat_fakes.FakeSettingsRepository(),
      ),
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
      home: const ChatThreadScreen(conversationId: 'conversation-1'),
    ),
  );
}

chat_fakes.FakeChatsRepository _chats({bool silent = true}) {
  final repository = silent ? _SilentChats() : chat_fakes.FakeChatsRepository();
  repository.conversations = const [
    ConversationSummary(
      id: 'conversation-1',
      type: ConversationType.group,
      unreadCount: 0,
      title: 'Friends',
    ),
  ];
  return repository;
}

Future<void> _selectRange(
  WidgetTester tester,
  String body,
  int start,
  int end,
) async {
  final editable = find.descendant(
    of: find.byKey(const ValueKey('quote-picker-text')),
    matching: find.byType(EditableText),
  );
  final state = tester.state<EditableTextState>(editable);
  state.userUpdateTextEditingValue(
    TextEditingValue(
      text: body,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    ),
    SelectionChangedCause.longPress,
  );
  await tester.pump();
}

Future<void> _pickMenu(WidgetTester tester, String entry) async {
  await tester.tap(find.byTooltip('Attach'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pump();
}

void main() {
  const body = 'The meeting moved to Friday at noon.';

  group('replying to part of a message', () {
    testWidgets('picks words, shows them in the reply bar and sends them', (
      tester,
    ) async {
      final repository = _chats()..messages = [_message('m1', body)];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.longPress(find.text(body));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('message-action-quote-reply')),
      );
      await tester.pumpAndSettle();

      // Nothing selected yet: the button does nothing.
      final reply = find.byKey(const ValueKey('quote-picker-reply'));
      await tester.tap(reply);
      await tester.pump();
      expect(find.byKey(const ValueKey('quote-picker-text')), findsOneWidget);

      await _selectRange(tester, body, 12, 27);
      await tester.tap(reply);
      await tester.pumpAndSettle();

      expect(find.text('Replying to moved to Friday'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Not Friday please');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(repository.sentReplyToMessageId, 'm1');
      final quote = repository.sentReplyPreview?.quote;
      expect(quote?.text, 'moved to Friday');
      expect(quote?.start, 12);
      expect(quote?.end, 27);
      expect(repository.sentReplyPreview?.body, body);
      expect(find.textContaining('Replying to'), findsNothing);
    });

    testWidgets('the sheet closed without a pick starts no reply', (
      tester,
    ) async {
      final repository = _chats()..messages = [_message('m1', body)];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.longPress(find.text(body));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('message-action-quote-reply')),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.textContaining('Replying to'), findsNothing);
    });

    testWidgets('a plain reply carries no quote', (tester) async {
      final repository = _chats()..messages = [_message('m1', body)];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.longPress(find.text(body));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sure');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(repository.sentReplyPreview?.quote, isNull);
    });

    testWidgets('a quoted reply shows the quote and jumps to the message', (
      tester,
    ) async {
      final repository = _chats()
        ..messages = [
          _message('m1', body),
          _message(
            'm2',
            'Friday is bad',
            senderId: 'user-1',
            minute: 1,
            replyPreview: const ReplyPreview(
              messageId: 'm1',
              senderName: 'Message',
              body: body,
              type: MessageType.text,
              quote: ReplyQuote(text: 'moved to Friday', start: 12, end: 27),
            ),
          ),
        ];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      // The quote stands for the start of the message.
      expect(find.text('moved to Friday'), findsOneWidget);
      final open = find.byKey(const ValueKey('reply-quote-open'));
      expect(open, findsOneWidget);
      expect(
        tester.widget<WeCordPressable>(open).hint,
        'Go to the message this answers',
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a deleted original shows no quote', (tester) async {
      final repository = _chats()
        ..messages = [
          _message('m1', body, recalledAt: DateTime.utc(2026, 5, 18, 5)),
          _message(
            'm2',
            'Friday is bad',
            senderId: 'user-1',
            minute: 1,
            replyPreview: const ReplyPreview(
              messageId: 'm1',
              senderName: 'Message',
              body: body,
              type: MessageType.text,
              quote: ReplyQuote(text: 'moved to Friday'),
            ),
          ),
        ];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      expect(find.text('moved to Friday'), findsNothing);
      expect(find.text('Message deleted'), findsWidgets);
      expect(find.byKey(const ValueKey('reply-quote-open')), findsNothing);
    });
  });

  group('sending silently', () {
    testWidgets('sends the text through the silent path and says so', (
      tester,
    ) async {
      final repository = _chats() as _SilentChats;
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Sleep well');
      await tester.pump();
      await _pickMenu(tester, 'Send silently');
      await tester.pump();

      expect(repository.silentSends.map((send) => send.body), ['Sleep well']);
      expect(repository.sentMessages, isEmpty);
      expect(find.text('Sent silently. Nobody was notified.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });

    testWidgets('an empty box asks for a message first', (tester) async {
      final repository = _chats() as _SilentChats;
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await _pickMenu(tester, 'Send silently');
      await tester.pump();

      expect(repository.silentSends, isEmpty);
      expect(find.text('Write a message to send silently.'), findsOneWidget);
    });

    testWidgets('a silent reply keeps its reply and quote', (tester) async {
      final repository = _chats() as _SilentChats
        ..messages = [_message('m1', body)];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.longPress(find.text(body));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sure');
      await tester.pump();
      await _pickMenu(tester, 'Send silently');
      await tester.pump();

      expect(repository.silentSends.single.replyTo, 'm1');
      expect(repository.silentSends.single.preview?.messageId, 'm1');
    });

    testWidgets('slash commands are not sent silently', (tester) async {
      final repository = _chats() as _SilentChats;
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '/poll');
      await tester.pump();
      await _pickMenu(tester, 'Send silently');
      await tester.pump();

      expect(repository.silentSends, isEmpty);
      expect(find.text("Commands can't be sent silently."), findsOneWidget);
    });

    testWidgets('a server without it does not offer the entry', (tester) async {
      final repository = _chats(silent: false);
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      expect(find.text('Send silently'), findsNothing);
      expect(find.text('Schedule message'), findsOneWidget);
    });

    testWidgets('own silent messages are marked, the others are not', (
      tester,
    ) async {
      final repository = _chats()
        ..messages = [
          _message('m1', 'shh from me', senderId: 'user-1', silent: true),
          _message('m2', 'shh from them', silent: true, minute: 1),
          _message('m3', 'loud from me', senderId: 'user-1', minute: 2),
        ];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      expect(find.byKey(const ValueKey('silent-mark')), findsOneWidget);
      expect(find.text('Sent silently'), findsOneWidget);
    });
  });

  group('pausing and trimming a recording', () {
    Future<_PausableRecorder> record(
      WidgetTester tester,
      chat_fakes.FakeChatsRepository repository,
    ) async {
      final recorder = _PausableRecorder(_wav(4000))
        ..nextRecording = RecordedVoiceMessage(
          bytes: _wav(4000),
          mimeType: 'audio/wav',
          durationMs: 4000,
        );
      await tester.pumpWidget(_app(repository, recorder: recorder));
      await tester.pump();
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pump();
      return recorder;
    }

    testWidgets('pause shows Paused and resume goes on', (tester) async {
      final repository = _chats();
      final recorder = await record(tester, repository);
      expect(find.text('Recording...'), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-voice-trim')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('composer-voice-pause')));
      await tester.pump();
      expect(recorder.isPaused, isTrue);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-voice-trim')), findsOneWidget);

      await tester.tap(find.byTooltip('Resume recording'));
      await tester.pump();
      expect(recorder.isPaused, isFalse);
      expect(find.text('Recording...'), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-voice-trim')), findsNothing);
    });

    testWidgets('a recorder that cannot pause has no pause button', (
      tester,
    ) async {
      final repository = _chats();
      await tester.pumpWidget(_app(repository));
      await tester.pump();
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pump();

      expect(find.text('Recording...'), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-voice-pause')), findsNothing);
    });

    testWidgets('trimming then sending sends only the kept part', (
      tester,
    ) async {
      final repository = _chats();
      final recorder = await record(tester, repository);
      await tester.tap(find.byKey(const ValueKey('composer-voice-pause')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('composer-voice-trim')));
      await tester.pumpAndSettle();
      expect(find.text('Trim voice message'), findsOneWidget);

      final slider = tester.widget<RangeSlider>(
        find.byKey(const ValueKey('voice-trim-slider')),
      );
      slider.onChanged!(const RangeValues(1000, 3000));
      await tester.pump();
      expect(find.text('Keeps 0:02.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-trim-done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('voice-trim-label')), findsOneWidget);
      expect(find.text('Keeps 0:02.0'), findsOneWidget);

      await tester.tap(find.byTooltip('Send voice message'));
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 1);
      final sent = repository.sentVoiceMessages.single;
      expect(sent.durationMs, 2000);
      // 2000 samples of 16 bits and the header.
      expect(sent.bytes.length, 44 + 4000);
      expect(sent.bytes.sublist(44), _wav(4000).sublist(44 + 2000, 44 + 6000));
    });

    testWidgets('keeping everything sends the recording as it is', (
      tester,
    ) async {
      final repository = _chats();
      await record(tester, repository);
      await tester.tap(find.byKey(const ValueKey('composer-voice-pause')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-voice-trim')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-trim-done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('voice-trim-label')), findsNothing);
      await tester.tap(find.byTooltip('Send voice message'));
      await tester.pumpAndSettle();
      expect(repository.sentVoiceMessages.single.durationMs, 4000);
      expect(repository.sentVoiceMessages.single.bytes, _wav(4000));
    });

    testWidgets('recording more after a trim drops the trim', (tester) async {
      final repository = _chats();
      await record(tester, repository);
      await tester.tap(find.byKey(const ValueKey('composer-voice-pause')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-voice-trim')));
      await tester.pumpAndSettle();
      tester
          .widget<RangeSlider>(find.byKey(const ValueKey('voice-trim-slider')))
          .onChanged!(const RangeValues(500, 2500));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-trim-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-trim-label')), findsOneWidget);

      await tester.tap(find.byTooltip('Resume recording'));
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-trim-label')), findsNothing);
    });
  });
}
