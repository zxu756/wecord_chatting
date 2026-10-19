import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/voice/captions/recap/meeting_recap_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Blocks a note holds at most when it is started from blocks (the server's
/// limit is 200).
const maxRecapNoteBlocks = 150;

/// "Oct 19" style date for titles, in the person's language.
String recapDateLabel(DateTime when) {
  if (AppStrings.isChinese) {
    return '${when.month}月${when.day}日';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[when.month - 1]} ${when.day}';
}

/// The note's title: the model's, or "Call recap · Oct 19".
String recapNoteTitle(String title, DateTime when) {
  final clean = title.trim();
  if (clean.isNotEmpty) {
    return clean;
  }
  return tr('Call recap · {date}', {'date': recapDateLabel(when)});
}

/// One to-do as a line of the note: "Send the plan - Ada, Mon 10:00".
String recapActionLine(
  ExtractedAction action, {
  required String? Function(String userId) nameOf,
}) {
  final parts = <String>[];
  for (final assignee in action.assignees) {
    final name = nameOf(assignee);
    if (name != null && name.isNotEmpty) {
      parts.add(name);
    }
  }
  final due = action.due;
  if (due != null) {
    final date = '${due.year}-${_two(due.month)}-${_two(due.day)}';
    parts.add(
      action.dueHasTime ? '$date ${_two(due.hour)}:${_two(due.minute)}' : date,
    );
  }
  return parts.isEmpty ? action.title : '${action.title} - ${parts.join(', ')}';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// The recap as the blocks of a new note: a line saying where it came from,
/// the key points, the decisions and the to-dos (unticked, so the note works
/// as a checklist). Sections with nothing in them are left out.
List<NoteTemplateBlock> buildRecapNoteBlocks(
  MeetingRecap recap, {
  required DateTime when,
  required int speakers,
  required String? Function(String userId) nameOf,
}) {
  NoteTemplateBlock block(NoteBlockKind kind, String text) =>
      NoteTemplateBlock(kind: kind, text: text);
  final blocks = <NoteTemplateBlock>[
    block(
      NoteBlockKind.paragraph,
      speakers > 0
          ? tr('From the captions of a call on {date}, {count} people spoke.', {
              'date': recapDateLabel(when),
              'count': speakers,
            })
          : tr('From the captions of a call on {date}.', {
              'date': recapDateLabel(when),
            }),
    ),
    if (recap.summary.isNotEmpty) ...[
      block(NoteBlockKind.heading2, tr('Summary')),
      for (final point in recap.summary) block(NoteBlockKind.bullet, point),
    ],
    if (recap.decisions.isNotEmpty) ...[
      block(NoteBlockKind.heading2, tr('Decisions')),
      for (final decision in recap.decisions)
        block(NoteBlockKind.bullet, decision),
    ],
    if (recap.actionItems.isNotEmpty) ...[
      block(NoteBlockKind.heading2, tr('Action items')),
      for (final action in recap.actionItems)
        block(NoteBlockKind.todo, recapActionLine(action, nameOf: nameOf)),
    ],
    if (recap.truncated)
      block(
        NoteBlockKind.paragraph,
        tr('The call was long, so part of the middle was not read.'),
      ),
  ];
  return blocks.length > maxRecapNoteBlocks
      ? blocks.sublist(0, maxRecapNoteBlocks)
      : blocks;
}
