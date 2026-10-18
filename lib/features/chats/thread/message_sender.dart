import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

/// Name and avatar shown above a group of incoming messages.
MessageSender senderFor(
  ChatMessage message,
  Map<String, GroupMember> membersById, {
  Profile? fallbackProfile,
}) {
  // Webhook messages show the webhook, never its creator's profile.
  if (message.webhookName case final webhookName?) {
    return MessageSender(
      name: webhookName,
      avatarUrl: message.webhookAvatarUrl,
      isBot: true,
    );
  }
  final member = membersById[message.senderId];
  final profile = message.sender ?? member?.profile ?? fallbackProfile;
  final nickname = (message.senderNickname ?? member?.nickname)?.trim() ?? '';
  final label = nickname.isNotEmpty
      ? nickname
      : profile?.displayLabel.trim() ?? '';
  return MessageSender(
    name: label.isNotEmpty
        ? label
        : profile?.username.trim().isNotEmpty == true
        ? profile!.username
        : tr('Unknown member'),
    avatarUrl: message.senderCircleAvatarUrl ?? profile?.avatarUrl,
    roleColor: message.senderRoleColor,
    userId: message.senderId,
  );
}

class MessageSender {
  const MessageSender({
    required this.name,
    this.avatarUrl,
    this.roleColor,
    this.isBot = false,
    this.userId,
  });

  final String name;
  final String? avatarUrl;

  /// The member behind the name (not set for webhooks), whose circle tag
  /// shows next to it.
  final String? userId;

  /// A webhook, marked with a BOT tag.
  final bool isBot;

  /// The sender's highest coloured circle role, as 0xRRGGBB.
  final int? roleColor;
}
