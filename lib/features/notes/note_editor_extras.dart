import 'package:flutter/foundation.dart';
import 'package:wecord/features/notes/note_comments_controller.dart';

/// Where a new comment goes: a block, and the words selected in it.
@immutable
class NoteCommentTarget {
  const NoteCommentTarget({
    required this.blockId,
    this.start,
    this.end,
    this.quote,
  });

  final String blockId;

  /// UTF-16 offsets of the selected words and the words themselves; all null
  /// for a comment on the whole block.
  final int? start;
  final int? end;
  final String? quote;
}

/// What the AI is asked to work on: the words selected in a block (or none:
/// the whole note), and where its answer goes.
@immutable
class NoteAssistTarget {
  const NoteAssistTarget({
    this.blockId,
    this.start,
    this.end,
    this.selectedText,
    this.replaceBlockId,
  });

  /// The block the selection is in, null when nothing is selected.
  final String? blockId;
  final int? start;
  final int? end;

  /// The selected words, null for none.
  final String? selectedText;

  /// An empty block (the `/` that opened the menu was cleared) that the
  /// answer takes the place of.
  final String? replaceBlockId;

  bool get hasSelection => selectedText != null && selectedText!.isNotEmpty;
}

/// The hooks the note editor offers to features beside it (comments, the
/// AI): without them the editor is what it was.
@immutable
class NoteEditorExtras {
  const NoteEditorExtras({
    this.comments,
    this.canComment = false,
    this.onComment,
    this.onOpenComments,
    this.onAssist,
  });

  /// The note's comments: open ones are highlighted and counted per block.
  final NoteCommentsController? comments;

  /// Whether the person may comment (a reader without edit rights may).
  final bool canComment;

  /// The person wants to comment on [NoteCommentTarget].
  final void Function(NoteCommentTarget target)? onComment;

  /// The person tapped the comment count of a block.
  final void Function(String blockId)? onOpenComments;

  /// The person asked the AI for something at [NoteAssistTarget].
  final void Function(NoteAssistTarget target)? onAssist;
}
