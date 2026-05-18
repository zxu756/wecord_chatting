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
    );
  }

  final Profile profile;
  final ProfileRelationshipStatus relationshipStatus;
  final String? incomingRequestId;
  final String? outgoingRequestId;
  final bool isBlockedByMe;
  final bool hasBlockedMe;

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
