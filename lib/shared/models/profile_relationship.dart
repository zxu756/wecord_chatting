import 'package:wecord/shared/models/profile.dart';

enum ProfileRelationshipStatus {
  self,
  none,
  friend,
  incomingRequest,
  outgoingRequest,
  blocked,
  blockedByThem;

  static ProfileRelationshipStatus fromJson(String? value) {
    return switch (value) {
      'self' => ProfileRelationshipStatus.self,
      'friend' => ProfileRelationshipStatus.friend,
      'incoming_request' => ProfileRelationshipStatus.incomingRequest,
      'outgoing_request' => ProfileRelationshipStatus.outgoingRequest,
      'blocked' => ProfileRelationshipStatus.blocked,
      'blocked_by_them' => ProfileRelationshipStatus.blockedByThem,
      _ => ProfileRelationshipStatus.none,
    };
  }
}

class ProfileSummary {
  const ProfileSummary({
    required this.profile,
    required this.relationshipStatus,
    required this.incomingRequestId,
    required this.outgoingRequestId,
    required this.isBlockedByMe,
    required this.hasBlockedMe,
    this.mutualFriends = const <MutualFriend>[],
    this.mutualCircles = const <MutualCircle>[],
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      profile: Profile.fromJson(_profileJson(json)),
      relationshipStatus: ProfileRelationshipStatus.fromJson(
        json['relationship_status'] as String?,
      ),
      incomingRequestId: json['incoming_request_id'] as String?,
      outgoingRequestId: json['outgoing_request_id'] as String?,
      isBlockedByMe: json['is_blocked_by_me'] as bool? ?? false,
      hasBlockedMe: json['has_blocked_me'] as bool? ?? false,
      mutualFriends: [
        for (final item in _maps(json['mutual_friends']))
          MutualFriend.fromJson(item),
      ],
      mutualCircles: [
        for (final item in _maps(json['mutual_circles']))
          MutualCircle.fromJson(item),
      ],
    );
  }

  final Profile profile;
  final ProfileRelationshipStatus relationshipStatus;
  final String? incomingRequestId;
  final String? outgoingRequestId;
  final bool isBlockedByMe;
  final bool hasBlockedMe;

  /// Friends of both the viewer and this user (empty on their own profile).
  final List<MutualFriend> mutualFriends;

  /// Circles both the viewer and this user are in.
  final List<MutualCircle> mutualCircles;

  bool get canStartChat =>
      relationshipStatus == ProfileRelationshipStatus.friend;

  bool get canSendFriendRequest =>
      relationshipStatus == ProfileRelationshipStatus.none;

  bool get canAcceptRequest =>
      relationshipStatus == ProfileRelationshipStatus.incomingRequest &&
      incomingRequestId != null;

  static Map<String, dynamic> _profileJson(Map<String, dynamic> json) {
    const fallbackTimestamp = '1970-01-01T00:00:00.000Z';
    return {
      ...json,
      'created_at': json['created_at'] ?? fallbackTimestamp,
      'updated_at': json['updated_at'] ?? fallbackTimestamp,
    };
  }
}

Iterable<Map<String, dynamic>> _maps(Object? value) {
  return value is List ? value.whereType<Map<String, dynamic>>() : const [];
}

/// A friend shared with someone, as their profile lists it.
class MutualFriend {
  const MutualFriend({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory MutualFriend.fromJson(Map<String, dynamic> json) {
    return MutualFriend(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String id;
  final String username;

  /// Their display name, or the viewer's alias for them.
  final String displayName;
  final String? avatarUrl;

  String get label => displayName.trim().isEmpty ? username : displayName;
}

/// A circle shared with someone, as their profile lists it.
class MutualCircle {
  const MutualCircle({required this.id, required this.name, this.avatarUrl});

  factory MutualCircle.fromJson(Map<String, dynamic> json) {
    return MutualCircle(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
}
