import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/voice/captions/caption_protocol.dart';
import 'package:wecord/features/voice/captions/captions_controller.dart';
import 'package:wecord/features/voice/captions/recap/meeting_recap_repository.dart';
import 'package:wecord/features/voice/captions/recap/recap_note.dart';
import 'package:wecord/shared/l10n/l10n.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  final when = DateTime(2026, 10, 19, 14, 30);
  String? names(String id) => {'u2': 'Bart'}[id];

  test('the recap becomes a checklist note', () {
    final blocks = buildRecapNoteBlocks(
      MeetingRecap(
        title: 'Sync',
        summary: const ['Point one', 'Point two'],
        decisions: const ['Ship it'],
        actionItems: [
          const ExtractedAction(title: 'Send the plan', assignees: ['u2']),
          ExtractedAction(
            title: 'Book a room',
            due: DateTime(2026, 10, 21, 10),
            dueHasTime: true,
          ),
          ExtractedAction(title: 'Order food', due: DateTime(2026, 10, 22)),
        ],
        truncated: true,
      ),
      when: when,
      speakers: 3,
      nameOf: names,
    );
    expect(blocks.map((b) => (b.kind, b.text)), [
      (
        NoteBlockKind.paragraph,
        'From the captions of a call on Oct 19, 3 people spoke.',
      ),
      (NoteBlockKind.heading2, 'Summary'),
      (NoteBlockKind.bullet, 'Point one'),
      (NoteBlockKind.bullet, 'Point two'),
      (NoteBlockKind.heading2, 'Decisions'),
      (NoteBlockKind.bullet, 'Ship it'),
      (NoteBlockKind.heading2, 'Action items'),
      (NoteBlockKind.todo, 'Send the plan - Bart'),
      (NoteBlockKind.todo, 'Book a room - 2026-10-21 10:00'),
      (NoteBlockKind.todo, 'Order food - 2026-10-22'),
      (
        NoteBlockKind.paragraph,
        'The call was long, so part of the middle was not read.',
      ),
    ]);
    // Every block is one the server accepts from a template.
    for (final block in blocks) {
      expect(block.toJson()['kind'], isNotEmpty);
      expect(block.text.length, lessThan(20000));
    }
  });

  test('empty sections are left out', () {
    final blocks = buildRecapNoteBlocks(
      const MeetingRecap(
        title: '',
        summary: ['Only this'],
        decisions: [],
        actionItems: [],
      ),
      when: when,
      speakers: 0,
      nameOf: names,
    );
    expect(blocks.map((b) => b.text), [
      'From the captions of a call on Oct 19.',
      'Summary',
      'Only this',
    ]);
  });

  test('a note never gets more blocks than the server takes', () {
    final blocks = buildRecapNoteBlocks(
      MeetingRecap(
        title: '',
        summary: [for (var i = 0; i < 400; i++) 'point $i'],
        decisions: const [],
        actionItems: const [],
      ),
      when: when,
      speakers: 1,
      nameOf: names,
    );
    expect(blocks.length, maxRecapNoteBlocks);
    expect(maxRecapNoteBlocks, lessThanOrEqualTo(200));
  });

  test('the title is the model\'s, or the date', () {
    expect(recapNoteTitle('  Budget sync ', when), 'Budget sync');
    expect(recapNoteTitle('', when), 'Call recap · Oct 19');
    AppStrings.isChinese = true;
    expect(recapNoteTitle('', when), '通话纪要 · 10月19日');
  });

  test('the transcript is written for the server in order and in seconds', () {
    final start = DateTime(2026, 10, 19, 14);
    final transcript = CaptionTranscript(
      lines: [
        CaptionLine(
          speakerId: 'u2',
          id: 0,
          text: 'Hello',
          at: start.add(const Duration(seconds: 5)),
        ),
        CaptionLine(
          speakerId: 'u1',
          id: 0,
          text: 'Hi',
          at: start.add(const Duration(minutes: 2)),
        ),
        CaptionLine(
          speakerId: 'u2',
          id: 1,
          text: 'Early',
          at: start.subtract(const Duration(seconds: 3)),
        ),
      ],
      startedAt: start,
      names: const {'u1': 'Ada', 'u2': 'Bart'},
      conversationId: 'conv-1',
    );
    expect(transcript.speakerCount, 2);
    expect(transcript.isEmpty, isFalse);
    expect(transcript.toRequestEntries(), [
      {'speaker': 'u2', 'text': 'Hello', 'at': 5},
      {'speaker': 'u1', 'text': 'Hi', 'at': 120},
      {'speaker': 'u2', 'text': 'Early', 'at': 0},
    ]);
  });
}
