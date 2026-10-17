import 'package:flutter/foundation.dart';

/// What a note block is. The names are the values stored in
/// `note_blocks.kind`.
enum NoteBlockKind {
  paragraph('paragraph'),
  heading1('h1'),
  heading2('h2'),
  heading3('h3'),
  bullet('bullet'),
  numbered('numbered'),
  todo('todo'),
  quote('quote'),
  code('code'),
  divider('divider'),
  image('image');

  const NoteBlockKind(this.value);

  final String value;

  static NoteBlockKind fromValue(Object? value) {
    for (final kind in values) {
      if (kind.value == value) {
        return kind;
      }
    }
    return paragraph;
  }

  /// Blocks that carry text the reader types.
  bool get hasText => this != divider && this != image;

  /// Blocks that continue as the same kind on Enter.
  bool get isListItem => this == bullet || this == numbered || this == todo;

  bool get isHeading =>
      this == heading1 || this == heading2 || this == heading3;
}

/// Inline formatting: a range of a block's text and what it is.
///
/// [type] is `b` (bold), `i` (italic), `s` (strike), `c` (code), `l:<url>`
/// (link) or `m:<user id>` (a mention of a person).
@immutable
class NoteMark {
  const NoteMark(this.start, this.end, this.type);

  factory NoteMark.fromJson(List<dynamic> json) {
    return NoteMark(
      (json[0] as num).toInt(),
      (json[1] as num).toInt(),
      json[2] as String,
    );
  }

  static const bold = 'b';
  static const italic = 'i';
  static const strike = 's';
  static const code = 'c';
  static const linkPrefix = 'l:';
  static const mentionPrefix = 'm:';

  final int start;
  final int end;
  final String type;

  bool get isLink => type.startsWith(linkPrefix);
  bool get isMention => type.startsWith(mentionPrefix);
  String get linkUrl => type.substring(linkPrefix.length);
  String get mentionUserId => type.substring(mentionPrefix.length);

  /// Typing next to a mark continues it, except links and mentions.
  bool get continuesWhenTyping => !isLink && !isMention;

  List<Object> toJson() => [start, end, type];

  @override
  bool operator ==(Object other) =>
      other is NoteMark &&
      other.start == start &&
      other.end == end &&
      other.type == type;

  @override
  int get hashCode => Object.hash(start, end, type);

  @override
  String toString() => 'NoteMark($start, $end, $type)';
}

/// One block of a note: the unit that is stored, ordered and merged.
@immutable
class NoteBlock {
  const NoteBlock({
    required this.id,
    required this.pos,
    this.kind = NoteBlockKind.paragraph,
    this.text = '',
    this.marks = const [],
    this.props = const {},
    this.rev = 0,
    this.deleted = false,
  });

  factory NoteBlock.fromJson(Map<String, dynamic> json) {
    return NoteBlock(
      id: json['id'] as String,
      pos: json['pos'] as String,
      kind: NoteBlockKind.fromValue(json['kind']),
      text: json['text'] as String? ?? '',
      marks: [
        for (final mark in (json['marks'] as List<dynamic>? ?? const []))
          if (mark is List && mark.length >= 3) NoteMark.fromJson(mark),
      ],
      props: Map<String, Object?>.from(
        (json['props'] as Map<String, dynamic>?) ?? const {},
      ),
      rev: (json['rev'] as num?)?.toInt() ?? 0,
      deleted: json['deleted'] == true,
    );
  }

  final String id;

  /// The fractional ordering key; blocks sort by (pos, id).
  final String pos;
  final NoteBlockKind kind;
  final String text;
  final List<NoteMark> marks;

  /// Kind specific: `checked` for todos, `lang` for code, `path`, `name`,
  /// `width` and `height` for pictures.
  final Map<String, Object?> props;

  /// The server's revision of this block; 0 for blocks not stored yet.
  final int rev;
  final bool deleted;

  bool get checked => props['checked'] == true;

  NoteBlock copyWith({
    String? pos,
    NoteBlockKind? kind,
    String? text,
    List<NoteMark>? marks,
    Map<String, Object?>? props,
    int? rev,
    bool? deleted,
  }) {
    return NoteBlock(
      id: id,
      pos: pos ?? this.pos,
      kind: kind ?? this.kind,
      text: text ?? this.text,
      marks: marks ?? this.marks,
      props: props ?? this.props,
      rev: rev ?? this.rev,
      deleted: deleted ?? this.deleted,
    );
  }

  /// Whether [other] says the same thing (revisions aside).
  bool sameContent(NoteBlock other) {
    return pos == other.pos &&
        kind == other.kind &&
        text == other.text &&
        deleted == other.deleted &&
        listEquals(marks, other.marks) &&
        mapEquals(props, other.props);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'pos': pos,
    'kind': kind.value,
    'text': text,
    'marks': [for (final mark in marks) mark.toJson()],
    'props': props,
    'rev': rev,
    'deleted': deleted,
  };

  /// A `put` operation for note_apply_ops, based on [baseRev].
  Map<String, Object?> toPutOp(int? baseRev) => {
    'op': 'put',
    'id': id,
    'base_rev': baseRev,
    'pos': pos,
    'kind': kind.value,
    'text': text,
    'marks': [for (final mark in marks) mark.toJson()],
    'props': props,
  };

  @override
  String toString() => 'NoteBlock($id, $pos, ${kind.value}, "$text", r$rev)';
}

/// Orders blocks the way every client and the server do.
int compareBlocks(NoteBlock a, NoteBlock b) {
  final byPos = a.pos.compareTo(b.pos);
  return byPos != 0 ? byPos : a.id.compareTo(b.id);
}

/// A note's own fields.
@immutable
class NoteMeta {
  const NoteMeta({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.icon,
    this.managersOnly = false,
    this.pinned = false,
    this.createdBy,
    this.updatedBy,
    this.updatedAt,
    this.canEdit = false,
    this.canManage = false,
  });

  factory NoteMeta.fromJson(Map<String, dynamic> json) {
    return NoteMeta(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? defaultIcon,
      managersOnly: json['managers_only'] == true,
      pinned: json['pinned'] == true,
      createdBy: json['created_by'] as String?,
      updatedBy: json['updated_by'] as String?,
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
      canEdit: json['can_edit'] == true,
      canManage: json['can_manage'] == true,
    );
  }

  static const defaultIcon = '\u{1F4DD}';

  final String id;
  final String conversationId;
  final String title;
  final String icon;
  final bool managersOnly;
  final bool pinned;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? updatedAt;
  final bool canEdit;
  final bool canManage;

  NoteMeta copyWith({
    String? title,
    String? icon,
    bool? managersOnly,
    bool? pinned,
    bool? canEdit,
    bool? canManage,
    DateTime? updatedAt,
  }) {
    return NoteMeta(
      id: id,
      conversationId: conversationId,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      managersOnly: managersOnly ?? this.managersOnly,
      pinned: pinned ?? this.pinned,
      createdBy: createdBy,
      updatedBy: updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      canEdit: canEdit ?? this.canEdit,
      canManage: canManage ?? this.canManage,
    );
  }
}

/// A note as listed in a conversation.
@immutable
class NoteSummary {
  const NoteSummary({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.icon,
    required this.managersOnly,
    required this.pinned,
    required this.canEdit,
    this.updatedAt,
    this.updatedByName,
    this.preview = '',
  });

  factory NoteSummary.fromJson(
    Map<String, dynamic> json, {
    required String conversationId,
  }) {
    return NoteSummary(
      id: json['id'] as String,
      conversationId: conversationId,
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? NoteMeta.defaultIcon,
      managersOnly: json['managers_only'] == true,
      pinned: json['pinned'] == true,
      canEdit: json['can_edit'] == true,
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
      updatedByName: json['updated_by_name'] as String?,
      preview: json['preview'] as String? ?? '',
    );
  }

  final String id;
  final String conversationId;
  final String title;
  final String icon;
  final bool managersOnly;
  final bool pinned;
  final bool canEdit;
  final DateTime? updatedAt;
  final String? updatedByName;
  final String preview;
}

/// A note found by title, for the quick switcher.
@immutable
class NoteSearchHit {
  const NoteSearchHit({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.icon,
    required this.conversationType,
    this.updatedAt,
    this.conversationTitle,
    this.circleId,
    this.circleName,
  });

  factory NoteSearchHit.fromJson(Map<String, dynamic> json) {
    return NoteSearchHit(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? NoteMeta.defaultIcon,
      conversationType: json['conversation_type'] as String? ?? 'direct',
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
      conversationTitle: json['conversation_title'] as String?,
      circleId: json['circle_id'] as String?,
      circleName: json['circle_name'] as String?,
    );
  }

  final String id;
  final String conversationId;
  final String title;
  final String icon;
  final String conversationType;
  final DateTime? updatedAt;
  final String? conversationTitle;
  final String? circleId;
  final String? circleName;
}

/// A snapshot in a note's history.
@immutable
class NoteVersionSummary {
  const NoteVersionSummary({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.title,
    required this.blockCount,
    this.label,
    this.createdByName,
  });

  factory NoteVersionSummary.fromJson(Map<String, dynamic> json) {
    return NoteVersionSummary(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      kind: json['kind'] as String? ?? 'auto',
      title: json['title'] as String? ?? '',
      blockCount: (json['block_count'] as num?)?.toInt() ?? 0,
      label: json['label'] as String?,
      createdByName: json['created_by_name'] as String?,
    );
  }

  final String id;
  final DateTime createdAt;

  /// `auto`, `manual` or `restore`.
  final String kind;
  final String title;
  final int blockCount;
  final String? label;
  final String? createdByName;
}

/// The contents of a snapshot.
@immutable
class NoteVersion {
  const NoteVersion({
    required this.id,
    required this.title,
    required this.icon,
    required this.blocks,
    required this.createdAt,
  });

  factory NoteVersion.fromJson(Map<String, dynamic> json) {
    return NoteVersion(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? NoteMeta.defaultIcon,
      createdAt: DateTime.parse(json['created_at'] as String),
      blocks: [
        for (final block in (json['blocks'] as List<dynamic>? ?? const []))
          NoteBlock.fromJson(Map<String, dynamic>.from(block as Map)),
      ]..sort(compareBlocks),
    );
  }

  final String id;
  final String title;
  final String icon;
  final DateTime createdAt;
  final List<NoteBlock> blocks;
}

/// A note with its blocks, as fetched.
@immutable
class NoteSnapshot {
  const NoteSnapshot({required this.note, required this.blocks});

  factory NoteSnapshot.fromJson(Map<String, dynamic> json) {
    return NoteSnapshot(
      note: NoteMeta.fromJson(Map<String, dynamic>.from(json['note'] as Map)),
      blocks: [
        for (final block in (json['blocks'] as List<dynamic>? ?? const []))
          NoteBlock.fromJson(Map<String, dynamic>.from(block as Map)),
      ]..sort(compareBlocks),
    );
  }

  final NoteMeta note;
  final List<NoteBlock> blocks;
}

/// The server's answer for one operation of note_apply_ops.
@immutable
class NoteOpResult {
  const NoteOpResult({
    required this.id,
    required this.status,
    this.rev,
    this.block,
    this.reason,
  });

  factory NoteOpResult.fromJson(Map<String, dynamic> json) {
    return NoteOpResult(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'rejected',
      rev: (json['rev'] as num?)?.toInt(),
      block: json['block'] is Map
          ? NoteBlock.fromJson(Map<String, dynamic>.from(json['block'] as Map))
          : null,
      reason: json['reason'] as String?,
    );
  }

  final String id;

  /// `ok`, `conflict` or `rejected`.
  final String status;
  final int? rev;

  /// The block as stored, for conflicts.
  final NoteBlock? block;
  final String? reason;

  bool get isOk => status == 'ok';
  bool get isConflict => status == 'conflict';
}

/// What a conversation's notes and lists hold, for the header and the
/// pinned note banner.
@immutable
class ConversationWorkspace {
  const ConversationWorkspace({
    this.notes = 0,
    this.pinnedNote,
    this.lists = 0,
    this.openTasks = 0,
    this.mine = 0,
    this.overdue = 0,
    this.canCreate = false,
  });

  factory ConversationWorkspace.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ConversationWorkspace(
      notes: count('notes'),
      pinnedNote: json['pinned_note'] is Map
          ? NoteMeta.fromJson(
              Map<String, dynamic>.from(json['pinned_note'] as Map),
            )
          : null,
      lists: count('lists'),
      openTasks: count('open_tasks'),
      mine: count('mine'),
      overdue: count('overdue'),
      canCreate: json['can_create'] == true,
    );
  }

  final int notes;
  final NoteMeta? pinnedNote;
  final int lists;
  final int openTasks;
  final int mine;
  final int overdue;
  final bool canCreate;
}
