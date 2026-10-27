import 'package:wecord/features/notes/note_merge.dart' show mergeText;
import 'package:wecord/features/whiteboard/whiteboard_models.dart';

/// Merges two people's changes to one element, key by key.
///
/// [base] is what both started from (null for an element both made),
/// [mine] the local version and [theirs] the one the server has. A key that
/// only one side changed takes that side's value, so one person moving a
/// sticky note and another changing its color both survive. A key both
/// changed: what [mine] set stands, because it is sent next on top of
/// [theirs]' revision and is the later action; the words of a sticky note or
/// a text merge like the words of a note (typing in different places both
/// stay, typing in the same place keeps theirs and puts mine next to it).
/// The result carries [theirs]' revision so it can be sent as the next change.
///
/// A stroke is never edited after it is drawn, only moved (`ox`, `oy`), so
/// strokes merge by construction.
WhiteboardElement mergeElements({
  required WhiteboardElement? base,
  required WhiteboardElement mine,
  required WhiteboardElement theirs,
}) {
  final origin = base?.data ?? const <String, Object?>{};
  final data = Map<String, Object?>.from(theirs.data);
  final keys = {...origin.keys, ...mine.data.keys};
  for (final key in keys) {
    final before = origin[key];
    final now = mine.data[key];
    if (deepEquals(before, now) &&
        origin.containsKey(key) == mine.data.containsKey(key)) {
      continue;
    }
    if (key == 't' &&
        before is String &&
        now is String &&
        theirs.data['t'] is String) {
      data['t'] = mergeText(
        base: before,
        baseMarks: const [],
        mine: now,
        mineMarks: const [],
        theirs: theirs.data['t']! as String,
        theirsMarks: const [],
      ).text;
      continue;
    }
    if (mine.data.containsKey(key)) {
      data[key] = now;
    } else {
      data.remove(key);
    }
  }
  final baseZ = base?.z;
  return WhiteboardElement(
    id: mine.id,
    kind: mine.kind,
    z: baseZ != null && mine.z != baseZ
        ? mine.z
        : (base == null ? mine.z : theirs.z),
    data: data,
    rev: theirs.rev,
    deleted: false,
  );
}
