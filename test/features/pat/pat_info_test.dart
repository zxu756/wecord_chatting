import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/pat/pat_info.dart';
import 'package:wecord/features/pat/pat_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

PatInfo _pat({
  String suffix = '',
  bool undone = false,
  String actor = 'ada',
  String target = 'bart',
}) {
  return PatInfo(
    actorId: actor,
    targetId: target,
    actorName: actor == 'ada' ? 'Ada' : 'Bart',
    targetName: target == 'bart' ? 'Bart' : 'Ada',
    suffix: suffix,
    undone: undone,
  );
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the attachment of a pat line', () {
    test('is read into a pat', () {
      final pat = PatInfo.maybeFromAttachment({
        'kind': 'pat',
        'actor_id': 'a',
        'target_id': 'b',
        'actor_name': 'Ada',
        'target_name': 'Bart',
        'suffix': "'s shoulder",
        'undone': true,
      });
      expect(pat?.actorId, 'a');
      expect(pat?.targetName, 'Bart');
      expect(pat?.suffix, "'s shoulder");
      expect(pat?.undone, isTrue);
    });

    test('is nothing for other attachments', () {
      expect(PatInfo.maybeFromAttachment(null), isNull);
      expect(PatInfo.maybeFromAttachment({'kind': 'call'}), isNull);
      expect(PatInfo.maybeFromAttachment({'kind': 'pat'}), isNull);
    });

    test('marks the system messages that are pats', () {
      ChatMessage message(MessageType type, Map<String, dynamic>? attachment) {
        return ChatMessage(
          id: 'm',
          conversationId: 'c',
          senderId: 'a',
          type: type,
          body: '',
          createdAt: DateTime.utc(2026, 10, 18),
          attachment: attachment,
        );
      }

      const attachment = {'kind': 'pat', 'actor_id': 'a', 'target_id': 'b'};
      expect(isPatMessage(message(MessageType.system, attachment)), isTrue);
      // Only the server makes them: a text can't be a pat.
      expect(isPatMessage(message(MessageType.text, attachment)), isFalse);
      expect(isPatMessage(message(MessageType.system, null)), isFalse);
    });
  });

  group('the sentence', () {
    test('You patted Ada', () {
      expect(patSentence(_pat(), currentUserId: 'ada'), 'You patted Bart');
    });

    test('adds the target\'s suffix', () {
      expect(
        patSentence(_pat(suffix: "'s shoulder"), currentUserId: 'ada'),
        "You patted Bart's shoulder",
      );
    });

    test('Bart patted you', () {
      expect(patSentence(_pat(), currentUserId: 'bart'), 'Ada patted you');
    });

    test('"\'s shoulder" reads as "your shoulder" to the patted person', () {
      expect(
        patSentence(_pat(suffix: "'s shoulder"), currentUserId: 'bart'),
        'Ada patted your shoulder',
      );
      expect(
        patSentence(_pat(suffix: '’s head'), currentUserId: 'bart'),
        'Ada patted your head',
      );
    });

    test('other suffixes follow after a space', () {
      expect(
        patSentence(_pat(suffix: 'on the head'), currentUserId: 'ada'),
        'You patted Bart on the head',
      );
      expect(
        patSentence(_pat(suffix: 'on the head'), currentUserId: 'bart'),
        'Ada patted you on the head',
      );
    });

    test('others in a group see both names', () {
      expect(
        patSentence(_pat(suffix: "'s shoulder"), currentUserId: 'cy'),
        "Ada patted Bart's shoulder",
      );
      expect(patSentence(_pat(), currentUserId: null), 'Ada patted Bart');
    });

    test('a pat that was taken back says so', () {
      expect(
        patSentence(_pat(undone: true), currentUserId: 'ada'),
        'You took back a pat',
      );
      expect(
        patSentence(_pat(undone: true), currentUserId: 'bart'),
        'Ada took back a pat',
      );
    });

    test('a missing name reads as Someone', () {
      expect(
        patSentence(
          const PatInfo(
            actorId: 'a',
            targetId: 'b',
            actorName: '',
            targetName: ' ',
          ),
          currentUserId: 'c',
        ),
        'Someone patted Someone',
      );
    });

    test('in Chinese', () {
      AppStrings.isChinese = true;
      expect(
        patSentence(_pat(suffix: '的肩膀'), currentUserId: 'ada'),
        '你拍了拍“Bart”的肩膀',
      );
      expect(
        patSentence(_pat(suffix: '的肩膀'), currentUserId: 'bart'),
        '“Ada”拍了拍你的肩膀',
      );
      expect(patSentence(_pat(), currentUserId: 'cy'), '“Ada”拍了拍“Bart”');
      expect(patSentence(_pat(undone: true), currentUserId: 'ada'), '你撤回了拍一拍');
    });
  });

  group('failures from the server', () {
    PatFailure failure(String code, String message) =>
        patFailureFrom(PostgrestException(message: message, code: code));

    test('are told apart', () {
      expect(failure('53400', 'pat_too_fast'), PatFailure.tooFast);
      expect(failure('53400', 'pat_too_many'), PatFailure.tooMany);
      expect(
        failure('42501', 'You cannot pat this person'),
        PatFailure.notAllowed,
      );
      expect(failure('22023', 'pat_undo_expired'), PatFailure.undoExpired);
      expect(failure('22023', 'Pat someone else'), PatFailure.notAllowed);
      expect(failure('XX000', 'boom'), PatFailure.other);
    });
  });
}
