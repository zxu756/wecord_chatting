/// Whether a member has read a message, as the sender is told.
enum ReadState {
  read,
  unread,

  /// The member turned read receipts off: nobody can tell.
  unknown;

  static ReadState fromWire(Object? value) => switch (value) {
    'read' => read,
    'unread' => unread,
    _ => unknown,
  };
}

/// One member in a message's read list.
class MemberReadStatus {
  const MemberReadStatus({
    required this.userId,
    required this.name,
    required this.state,
    this.avatarUrl,
  });

  factory MemberReadStatus.fromJson(Map<String, dynamic> json) {
    final name = (json['display_name'] as String?)?.trim();
    return MemberReadStatus(
      userId: json['user_id'] as String,
      name: name != null && name.isNotEmpty
          ? name
          : (json['username'] as String? ?? ''),
      avatarUrl: json['avatar_url'] as String?,
      state: ReadState.fromWire(json['status']),
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;
  final ReadState state;
}

/// Why the read list or the reminder could not be had.
enum ReadStatusProblem {
  /// The viewer turned their own read receipts off.
  receiptsOff,

  /// The message has no list: not theirs, a direct chat, a channel, a group
  /// of more than 200, deleted, expired ...
  unavailable,
  alreadyReminded,
  nobodyToRemind,
  rateLimited,
  other,
}

class ReadStatusException implements Exception {
  const ReadStatusException(this.problem);

  final ReadStatusProblem problem;

  @override
  String toString() => 'ReadStatusException($problem)';
}

/// The members of a read list by state, in the list's order.
class ReadList {
  ReadList(List<MemberReadStatus> members)
    : read = [
        for (final m in members)
          if (m.state == ReadState.read) m,
      ],
      unread = [
        for (final m in members)
          if (m.state == ReadState.unread) m,
      ],
      unknown = [
        for (final m in members)
          if (m.state == ReadState.unknown) m,
      ];

  final List<MemberReadStatus> read;
  final List<MemberReadStatus> unread;
  final List<MemberReadStatus> unknown;
}
