enum FriendRequestStatus {
  pending,
  accepted,
  rejected,
  cancelled;

  factory FriendRequestStatus.fromJson(String value) {
    return switch (value) {
      'pending' => FriendRequestStatus.pending,
      'accepted' => FriendRequestStatus.accepted,
      'rejected' => FriendRequestStatus.rejected,
      'cancelled' => FriendRequestStatus.cancelled,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Unknown friend request status',
      ),
    };
  }

  String toJson() {
    return switch (this) {
      FriendRequestStatus.pending => 'pending',
      FriendRequestStatus.accepted => 'accepted',
      FriendRequestStatus.rejected => 'rejected',
      FriendRequestStatus.cancelled => 'cancelled',
    };
  }
}

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] as String,
      requesterId: json['requester_id'] as String,
      receiverId: json['receiver_id'] as String,
      status: FriendRequestStatus.fromJson(json['status'] as String),
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
    );
  }

  final String id;
  final String requesterId;
  final String receiverId;
  final FriendRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'requester_id': requesterId,
      'receiver_id': receiverId,
      'status': status.toJson(),
    };
  }

  FriendRequest copyWith({
    String? id,
    String? requesterId,
    String? receiverId,
    FriendRequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FriendRequest(
      id: id ?? this.id,
      requesterId: requesterId ?? this.requesterId,
      receiverId: receiverId ?? this.receiverId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime _parseTimestamp(Object? value) {
  return DateTime.parse(value as String).toUtc();
}
