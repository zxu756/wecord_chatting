import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// One line of a chain: a person and the note they added.
@immutable
class ChainEntry {
  const ChainEntry({
    required this.id,
    required this.userId,
    required this.name,
    this.note = '',
    this.avatarUrl,
    this.createdAt,
  });

  factory ChainEntry.fromJson(Map<String, dynamic> json) {
    return ChainEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: (json['name'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.tryParse('${json['created_at']}'),
    );
  }

  final String id;
  final String userId;
  final String name;
  final String note;
  final String? avatarUrl;
  final DateTime? createdAt;

  String get displayName => name.trim().isEmpty ? tr('Someone') : name.trim();

  /// "Ada bring snacks": the line without its number.
  String get text => note.trim().isEmpty ? displayName : '$displayName $note';
}

/// A chain and its lines, as `get_chain` answers.
@immutable
class ChainSnapshot {
  const ChainSnapshot({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.entries,
    required this.createdBy,
    this.messageId,
    this.description = '',
    this.example = '',
    this.deadline,
    this.maxEntries,
    this.closedByServer = false,
    this.creatorName = '',
    this.canManage = false,
    this.myEntryId,
  });

  factory ChainSnapshot.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    return ChainSnapshot(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      messageId: json['message_id'] as String?,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      example: (json['example'] as String?) ?? '',
      deadline: json['deadline'] == null
          ? null
          : DateTime.tryParse('${json['deadline']}'),
      maxEntries: (json['max_entries'] as num?)?.toInt(),
      closedByServer: json['closed'] == true,
      createdBy: json['created_by'] as String,
      creatorName: (json['creator_name'] as String?) ?? '',
      canManage: json['can_manage'] == true,
      myEntryId: json['my_entry_id'] as String?,
      entries: [
        if (rawEntries is List)
          for (final entry in rawEntries)
            if (entry is Map<String, dynamic>) ChainEntry.fromJson(entry),
      ],
    );
  }

  final String id;
  final String conversationId;
  final String? messageId;
  final String title;
  final String description;
  final String example;
  final DateTime? deadline;
  final int? maxEntries;
  final bool closedByServer;
  final String createdBy;
  final String creatorName;
  final bool canManage;
  final String? myEntryId;
  final List<ChainEntry> entries;

  /// Closed by hand, or the deadline has passed ([now] decides the second,
  /// so a card flips without waiting for the server).
  bool isClosed(DateTime now) =>
      closedByServer || (deadline != null && !deadline!.isAfter(now));

  bool get isFull => maxEntries != null && entries.length >= maxEntries!;

  ChainEntry? get myEntry =>
      entries.where((entry) => entry.id == myEntryId).firstOrNull;

  int get seatsLeft => maxEntries == null ? -1 : maxEntries! - entries.length;

  /// The list as plain text, to copy or export:
  ///
  ///     Saturday hike sign-up
  ///     1. Ada bring snacks
  ///     2. Bob
  String exportText() {
    final lines = [
      title,
      if (entries.isEmpty) tr('Nobody has joined yet.'),
      for (final (index, entry) in entries.indexed)
        '${index + 1}. ${entry.text}',
    ];
    return lines.join('\n');
  }
}

/// What a chain card in a chat points at (the message's attachment).
@immutable
class ChainCard {
  const ChainCard({required this.chainId, this.title = ''});

  final String chainId;
  final String title;

  static ChainCard? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null || attachment['kind'] != 'chain') {
      return null;
    }
    final id = attachment['chain_id'];
    if (id is! String) {
      return null;
    }
    return ChainCard(chainId: id, title: attachment['title'] as String? ?? '');
  }
}

extension ChainMessageCard on ChatMessage {
  /// The chain this message is the card of, or null.
  ChainCard? get chainCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return ChainCard.maybeFromAttachment(attachment);
  }
}

/// What the person chose in the chain form.
@immutable
class ChainDraft {
  const ChainDraft({
    required this.title,
    this.description = '',
    this.example = '',
    this.deadline,
    this.maxEntries,
  });

  final String title;
  final String description;
  final String example;
  final DateTime? deadline;
  final int? maxEntries;
}

/// The answer of a write: the note was dropped when the circle's AI guard
/// holds free text of new members.
@immutable
class ChainWriteResult {
  const ChainWriteResult({this.noteHeld = false});

  final bool noteHeld;
}

enum ChainFailureKind {
  closed,
  full,
  alreadyJoined,
  notJoined,
  notAllowed,
  tooLong,
  badDeadline,
  forbidden,
  gone,
  other,
}

/// A write the server refused.
class ChainException implements Exception {
  const ChainException(this.kind);

  /// Reads the server's refusal (see the chain migration's error texts).
  factory ChainException.fromPostgrest(PostgrestException error) {
    final text = error.message;
    final kind = switch (text) {
      'chain_closed' => ChainFailureKind.closed,
      'chain_full' => ChainFailureKind.full,
      'chain_already_joined' => ChainFailureKind.alreadyJoined,
      'chain_not_joined' => ChainFailureKind.notJoined,
      'chain_not_allowed' => ChainFailureKind.notAllowed,
      'chain_text_too_long' => ChainFailureKind.tooLong,
      'chain_deadline_invalid' => ChainFailureKind.badDeadline,
      'Chain not found' || 'Conversation not found' => ChainFailureKind.gone,
      _ when error.code == '42501' => ChainFailureKind.forbidden,
      _ => ChainFailureKind.other,
    };
    return ChainException(kind);
  }

  final ChainFailureKind kind;

  /// What to tell the person.
  String get message => switch (kind) {
    ChainFailureKind.closed => tr('This chain is closed.'),
    ChainFailureKind.full => tr('This chain is full.'),
    ChainFailureKind.alreadyJoined => tr('You are already in this chain.'),
    ChainFailureKind.notJoined => tr("You aren't in this chain."),
    ChainFailureKind.notAllowed => tr(
      'Chains work in groups and circle channels.',
    ),
    ChainFailureKind.tooLong => tr('That is too long.'),
    ChainFailureKind.badDeadline => tr('Pick a deadline in the future.'),
    ChainFailureKind.forbidden => tr("You can't do that here."),
    ChainFailureKind.gone => tr("This chain isn't available any more."),
    ChainFailureKind.other => tr("That didn't work. Try again."),
  };

  @override
  String toString() => 'ChainException($kind)';
}
