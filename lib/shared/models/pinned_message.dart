import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

class PinnedMessage {
  const PinnedMessage({
    required this.message,
    required this.sender,
    required this.pinnedAt,
    this.pinnedBy,
    this.pinnedByName,
  });

  factory PinnedMessage.fromJson(Map<String, dynamic> json) {
    return PinnedMessage(
      message: ChatMessage.fromJson(
        Map<String, dynamic>.from(json['message'] as Map),
      ),
      sender: Profile.fromJson(
        Map<String, dynamic>.from(json['sender'] as Map),
      ),
      pinnedBy: json['pinned_by'] as String?,
      pinnedByName: json['pinned_by_name'] as String?,
      pinnedAt: DateTime.parse(json['pinned_at'] as String).toUtc(),
    );
  }

  final ChatMessage message;
  final Profile sender;
  final String? pinnedBy;
  final String? pinnedByName;
  final DateTime pinnedAt;
}
