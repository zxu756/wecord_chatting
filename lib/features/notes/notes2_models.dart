import 'package:flutter/foundation.dart';
import 'package:wecord/features/notes/note_models.dart';

/// A comment on a note, or a reply under one (notes 2.0). The server decides
/// what the person may do with it ([canEdit], [canDelete], [canResolve]).
@immutable
class NoteComment {
  const NoteComment({
    required this.id,
    required this.noteId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.blockId,
    this.anchorStart,
    this.anchorEnd,
    this.anchorText,
    this.authorAvatarUrl,
    this.mentions = const [],
    this.editedAt,
    this.resolvedAt,
    this.resolvedByName,
    this.canEdit = false,
    this.canDelete = false,
    this.canResolve = false,
  });

  factory NoteComment.fromJson(Map<String, dynamic> json) {
    return NoteComment(
      id: json['id'] as String,
      noteId: json['note_id'] as String? ?? '',
      parentId: json['parent_id'] as String?,
      blockId: json['block_id'] as String?,
      anchorStart: (json['anchor_start'] as num?)?.toInt(),
      anchorEnd: (json['anchor_end'] as num?)?.toInt(),
      anchorText: json['anchor_text'] as String?,
      authorId: json['author_id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      authorAvatarUrl: json['author_avatar_url'] as String?,
      body: json['body'] as String? ?? '',
      mentions: [
        for (final id in (json['mentions'] as List<dynamic>? ?? const []))
          if (id is String) id,
      ],
      createdAt:
          DateTime.tryParse('${json['created_at']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      editedAt: DateTime.tryParse('${json['edited_at']}'),
      resolvedAt: DateTime.tryParse('${json['resolved_at']}'),
      resolvedByName: json['resolved_by_name'] as String?,
      canEdit: json['can_edit'] == true,
      canDelete: json['can_delete'] == true,
      canResolve: json['can_resolve'] == true,
    );
  }

  final String id;
  final String noteId;
  final String? parentId;

  /// The block it is about, the stretch of its text ([anchorStart] to
  /// [anchorEnd], UTF-16 offsets) and the words it was made on.
  final String? blockId;
  final int? anchorStart;
  final int? anchorEnd;
  final String? anchorText;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final String body;
  final List<String> mentions;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? resolvedAt;
  final String? resolvedByName;
  final bool canEdit;
  final bool canDelete;
  final bool canResolve;

  bool get isReply => parentId != null;
  bool get isResolved => resolvedAt != null;
  bool get hasRange => anchorStart != null && anchorEnd != null;
}

/// A comment with the replies under it.
@immutable
class NoteCommentThread {
  const NoteCommentThread({required this.root, this.replies = const []});

  final NoteComment root;
  final List<NoteComment> replies;

  bool get isResolved => root.isResolved;

  /// Comments in the thread, replies included.
  int get length => 1 + replies.length;

  /// When the thread last moved.
  DateTime get lastActivity => replies.isEmpty
      ? root.createdAt
      : replies.last.createdAt.isAfter(root.createdAt)
      ? replies.last.createdAt
      : root.createdAt;
}

/// Groups a flat list (oldest first) into threads, oldest thread first. A
/// reply whose comment is not there (hidden, deleted) is left out.
List<NoteCommentThread> groupCommentThreads(List<NoteComment> comments) {
  final replies = <String, List<NoteComment>>{};
  for (final comment in comments) {
    final parent = comment.parentId;
    if (parent != null) {
      replies.putIfAbsent(parent, () => []).add(comment);
    }
  }
  for (final list in replies.values) {
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  return [
    for (final comment in comments)
      if (!comment.isReply)
        NoteCommentThread(root: comment, replies: replies[comment.id] ?? []),
  ];
}

/// Where a comment sits in a block's text: the highlighted stretch.
@immutable
class NoteCommentAnchor {
  const NoteCommentAnchor({
    required this.commentId,
    required this.start,
    required this.end,
  });

  final String commentId;
  final int start;
  final int end;
}

/// The stretch of [block]'s text that [comment] was made on, if the words are
/// still where they were (an edit that moved or changed them drops the
/// highlight; the comment stays on the block).
NoteCommentAnchor? anchorIn(NoteBlock block, NoteComment comment) {
  final start = comment.anchorStart;
  final end = comment.anchorEnd;
  final quote = comment.anchorText;
  if (comment.blockId != block.id ||
      start == null ||
      end == null ||
      quote == null ||
      end > block.text.length ||
      start >= end) {
    return null;
  }
  if (block.text.substring(start, end) != quote) {
    return null;
  }
  return NoteCommentAnchor(commentId: comment.id, start: start, end: end);
}

/// A personal note template (blocks are fetched with [Notes2Repository.getTemplate]).
@immutable
class NoteTemplateSummary {
  const NoteTemplateSummary({
    required this.id,
    required this.name,
    required this.icon,
    required this.title,
    required this.blockCount,
  });

  factory NoteTemplateSummary.fromJson(Map<String, dynamic> json) {
    return NoteTemplateSummary(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? NoteMeta.defaultIcon,
      title: json['title'] as String? ?? '',
      blockCount: (json['block_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String icon;
  final String title;
  final int blockCount;
}

/// One block of a template: what a new note starts with.
@immutable
class NoteTemplateBlock {
  const NoteTemplateBlock({
    required this.kind,
    this.text = '',
    this.marks = const [],
    this.props = const {},
  });

  factory NoteTemplateBlock.fromJson(Map<String, dynamic> json) {
    return NoteTemplateBlock(
      kind: NoteBlockKind.fromValue(json['kind']),
      text: json['text'] as String? ?? '',
      marks: [
        for (final mark in (json['marks'] as List<dynamic>? ?? const []))
          if (mark is List && mark.length >= 3) NoteMark.fromJson(mark),
      ],
      props: Map<String, Object?>.from(
        (json['props'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  final NoteBlockKind kind;
  final String text;
  final List<NoteMark> marks;
  final Map<String, Object?> props;

  Map<String, Object?> toJson() => {
    'kind': kind.value,
    'text': text,
    'marks': [for (final mark in marks) mark.toJson()],
    'props': props,
  };
}

/// A template with its blocks, built in or personal.
@immutable
class NoteTemplate {
  const NoteTemplate({
    required this.name,
    required this.icon,
    required this.title,
    required this.blocks,
    this.id,
  });

  factory NoteTemplate.fromJson(Map<String, dynamic> json) {
    return NoteTemplate(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? NoteMeta.defaultIcon,
      title: json['title'] as String? ?? '',
      blocks: [
        for (final block in (json['blocks'] as List<dynamic>? ?? const []))
          if (block is Map)
            NoteTemplateBlock.fromJson(Map<String, dynamic>.from(block)),
      ],
    );
  }

  /// Null for the built-in ones.
  final String? id;
  final String name;
  final String icon;
  final String title;
  final List<NoteTemplateBlock> blocks;
}

/// Whether and how a note is published as a web page.
@immutable
class NotePublication {
  const NotePublication({
    this.published = false,
    this.canPublish = false,
    this.canWithdraw = false,
    this.token,
    this.allowIndexing = false,
    this.publishedAt,
    this.publishedByName,
  });

  factory NotePublication.fromJson(Map<String, dynamic> json) {
    return NotePublication(
      published: json['published'] == true,
      canPublish: json['can_publish'] == true,
      canWithdraw: json['can_withdraw'] == true,
      token: json['token'] as String?,
      allowIndexing: json['allow_indexing'] == true,
      publishedAt: DateTime.tryParse('${json['published_at']}'),
      publishedByName: json['published_by_name'] as String?,
    );
  }

  final bool published;
  final bool canPublish;
  final bool canWithdraw;

  /// The secret of the link; only people who can edit the note get it.
  final String? token;
  final bool allowIndexing;
  final DateTime? publishedAt;
  final String? publishedByName;
}

/// A mention of me in a comment, or a reply to mine.
@immutable
class NoteCommentNotification {
  const NoteCommentNotification({
    required this.id,
    required this.kind,
    required this.commentId,
    required this.noteId,
    required this.conversationId,
    required this.noteTitle,
    required this.noteIcon,
    required this.actorName,
    required this.snippet,
    required this.createdAt,
    required this.isUnread,
    this.actorAvatarUrl,
  });

  factory NoteCommentNotification.fromJson(Map<String, dynamic> json) {
    return NoteCommentNotification(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'mention',
      commentId: json['comment_id'] as String? ?? '',
      noteId: json['note_id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      noteTitle: json['note_title'] as String? ?? '',
      noteIcon: json['note_icon'] as String? ?? NoteMeta.defaultIcon,
      actorName: json['actor_name'] as String? ?? '',
      actorAvatarUrl: json['actor_avatar_url'] as String?,
      snippet: json['snippet'] as String? ?? '',
      createdAt:
          DateTime.tryParse('${json['created_at']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isUnread: json['is_unread'] == true,
    );
  }

  final String id;

  /// `mention` or `reply`.
  final String kind;
  final String commentId;
  final String noteId;
  final String conversationId;
  final String noteTitle;
  final String noteIcon;
  final String actorName;
  final String? actorAvatarUrl;
  final String snippet;
  final DateTime createdAt;
  final bool isUnread;

  bool get isReply => kind == 'reply';
}
