class Friendship {
  const Friendship({
    required this.id,
    required this.userLowId,
    required this.userHighId,
    required this.createdAt,
    this.userLowRemark,
    this.userHighRemark,
  });

  factory Friendship.fromJson(Map<String, dynamic> json) {
    return Friendship(
      id: json['id'] as String,
      userLowId: json['user_low_id'] as String,
      userHighId: json['user_high_id'] as String,
      userLowRemark: json['user_low_remark'] as String?,
      userHighRemark: json['user_high_remark'] as String?,
      createdAt: _parseTimestamp(json['created_at']),
    );
  }

  final String id;
  final String userLowId;
  final String userHighId;
  final String? userLowRemark;
  final String? userHighRemark;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'user_low_id': userLowId,
      'user_high_id': userHighId,
      'user_low_remark': userLowRemark,
      'user_high_remark': userHighRemark,
    };
  }

  Friendship copyWith({
    String? id,
    String? userLowId,
    String? userHighId,
    String? userLowRemark,
    String? userHighRemark,
    DateTime? createdAt,
  }) {
    return Friendship(
      id: id ?? this.id,
      userLowId: userLowId ?? this.userLowId,
      userHighId: userHighId ?? this.userHighId,
      userLowRemark: userLowRemark ?? this.userLowRemark,
      userHighRemark: userHighRemark ?? this.userHighRemark,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

DateTime _parseTimestamp(Object? value) {
  return DateTime.parse(value as String).toUtc();
}
