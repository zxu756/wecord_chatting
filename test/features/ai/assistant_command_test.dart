import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/assistant/assistant_command.dart';
import 'package:wecord/features/ai/assistant/assistant_repository.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_origin.dart';

/// The mention syntax is read by the database (migration 202610230410) and by
/// the app; both must agree, so this is the table the SQL behaviour script
/// (test/supabase/ai_assistant_behaviour.sql) uses too.
void main() {
  group('the mention', () {
    test('is found in the texts the database accepts', () {
      for (final (text, range) in <(String, AssistantRange)>[
        ('@WeCord AI summarize', AssistantRange.thisMessage),
        ('@wecord ai hello', AssistantRange.thisMessage),
        ('@wecord_ai hello', AssistantRange.thisMessage),
        ('hey @WeCord AI, what now?', AssistantRange.thisMessage),
        ('@WeCord AI /20 what did we decide', AssistantRange.last20),
        ('@WeCord AI /100', AssistantRange.last100),
        ('@WeCord AI   /20 x', AssistantRange.last20),
        ('@WeCord AI总结一下', AssistantRange.thisMessage),
        ('@WeCord AI /50 x', AssistantRange.thisMessage),
        ('@WeCord AI /200 x', AssistantRange.thisMessage),
      ]) {
        expect(mentionsAssistant(text), isTrue, reason: text);
        expect(assistantRangeOf(text), range, reason: text);
      }
    });

    test('is not found in the texts the database ignores', () {
      for (final text in [
        'see me@wecord ai.example',
        '@WeCord AIs rule',
        'WeCord AI is great',
        '@everyone',
        '',
      ]) {
        expect(mentionsAssistant(text), isFalse, reason: text);
        expect(assistantRangeOf(text), isNull, reason: text);
      }
    });

    test('is written with the range after it', () {
      expect(
        assistantMessageText(AssistantRange.thisMessage, ' summarize '),
        '@WeCord AI summarize',
      );
      expect(
        assistantMessageText(AssistantRange.last20, 'what did we decide?'),
        '@WeCord AI /20 what did we decide?',
      );
      expect(
        assistantMessageText(AssistantRange.last100, 'list the to-dos'),
        '@WeCord AI /100 list the to-dos',
      );
      // What the app writes is what the app reads back.
      for (final range in AssistantRange.values) {
        expect(assistantRangeOf(assistantMessageText(range, 'q')), range);
      }
    });
  });

  group('a request to the assistant', () {
    test('says what is happening', () {
      const waiting = AssistantJobStatus(status: 'queued');
      expect(waiting.thinking, isTrue);
      expect(waiting.noAnswerText, isNull);
      const done = AssistantJobStatus(status: 'done');
      expect(done.answered, isTrue);
      expect(done.noAnswerText, isNull);
    });

    test('explains why there was no answer', () {
      String? why(String reason, [String status = 'skipped']) =>
          AssistantJobStatus(status: status, reason: reason).noAnswerText;
      expect(why('circle_off'), contains('circle'));
      expect(why('group_off'), contains('group owner'));
      expect(why('user_off'), contains('Settings'));
      expect(why('limit', 'limited'), contains('limit'));
      expect(why('rate_limited'), contains('too quickly'));
      expect(why('provider', 'failed'), contains("couldn't answer"));
      expect(why('timeout', 'failed'), contains("couldn't answer"));
      // Nothing to say about a question that was deleted or is old.
      expect(why('message_gone'), isNull);
      expect(why('stale'), isNull);
      expect(why('not_member'), isNull);
    });
  });

  test('an AI answer carries who asked and the items it listed', () {
    final reply = MessageAiReply.maybeFromJson({
      'kind': 'todos',
      'requester_id': 'user-1',
      'requester_name': 'Ada',
      'items': [
        {'title': 'Book the train'},
        'junk',
      ],
    });
    expect(reply!.kind, AiReplyKind.todos);
    expect(reply.requesterName, 'Ada');
    expect(reply.items, hasLength(1));
    expect(MessageAiReply.maybeFromJson(null), isNull);
    expect(MessageAiReply.maybeFromJson('x'), isNull);
    expect(
      MessageAiReply.maybeFromJson({'kind': 'poem'})!.kind,
      AiReplyKind.answer,
    );
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'ai',
      'type': 'text',
      'body': 'Here you go',
      'created_at': '2026-10-19T10:00:00Z',
      'ai_reply': {'kind': 'summary', 'requester_name': 'Ada'},
    });
    expect(message.aiReply!.kind, AiReplyKind.summary);
    expect(message.copyWith(body: 'edited').aiReply, isNotNull);
    expect(
      ChatMessage.fromJson({
        'id': 'm2',
        'conversation_id': 'c1',
        'sender_id': 'u',
        'type': 'text',
        'body': 'hi',
        'created_at': '2026-10-19T10:00:00Z',
      }).aiReply,
      isNull,
    );
  });
}
