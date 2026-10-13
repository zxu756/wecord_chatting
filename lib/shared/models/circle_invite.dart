class CircleInvite {
  const CircleInvite({
    required this.code,
    required this.circleId,
    required this.createdAt,
    required this.useCount,
    this.createdBy,
    this.createdByName,
    this.expiresAt,
    this.maxUses,
  });

  factory CircleInvite.fromJson(Map<String, dynamic> json) {
    return CircleInvite(
      code: json['code'] as String,
      circleId: json['circle_id'] as String,
      createdBy: json['created_by'] as String?,
      createdByName: json['created_by_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      expiresAt: _parseOptionalTimestamp(json['expires_at']),
      maxUses: (json['max_uses'] as num?)?.toInt(),
      useCount: (json['use_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String code;
  final String circleId;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int? maxUses;
  final int useCount;
}

enum CircleInviteInvalidReason {
  notFound('not_found'),
  expired('expired'),
  revoked('revoked'),
  exhausted('exhausted');

  const CircleInviteInvalidReason(this.value);

  final String value;

  static CircleInviteInvalidReason? fromValue(String? value) {
    if (value == null) {
      return null;
    }
    for (final reason in values) {
      if (reason.value == value) {
        return reason;
      }
    }
    return CircleInviteInvalidReason.notFound;
  }
}

class CircleInvitePreview {
  const CircleInvitePreview({
    required this.code,
    required this.alreadyMember,
    this.circle,
    this.invalidReason,
    this.expiresAt,
  });

  factory CircleInvitePreview.fromJson(Map<String, dynamic> json) {
    final circle = json['circle'];
    return CircleInvitePreview(
      code: json['code'] as String,
      alreadyMember: json['already_member'] as bool? ?? false,
      invalidReason: CircleInviteInvalidReason.fromValue(
        json['invalid_reason'] as String?,
      ),
      expiresAt: _parseOptionalTimestamp(json['expires_at']),
      circle: circle is Map
          ? CircleInvitePreviewCircle.fromJson(
              Map<String, dynamic>.from(circle),
            )
          : null,
    );
  }

  final String code;
  final bool alreadyMember;
  final CircleInvitePreviewCircle? circle;
  final CircleInviteInvalidReason? invalidReason;
  final DateTime? expiresAt;

  bool get canJoin =>
      circle != null && (alreadyMember || invalidReason == null);
}

class CircleInvitePreviewCircle {
  const CircleInvitePreviewCircle({
    required this.id,
    required this.name,
    required this.memberCount,
    this.avatarUrl,
  });

  factory CircleInvitePreviewCircle.fromJson(Map<String, dynamic> json) {
    return CircleInvitePreviewCircle(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final int memberCount;
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.parse(value).toUtc();
}
