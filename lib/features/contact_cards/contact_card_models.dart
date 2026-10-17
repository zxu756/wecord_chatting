import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// Whom a contact card is about.
enum ContactCardKind { user, circle }

/// A person or a circle sent as a card (the attachment of a message,
/// `202610180071_contact_cards.sql`).
///
/// A person's card is a snapshot of what chat shows of anyone: name,
/// @username and avatar. A circle's card carries an invite that the card's
/// Join opens.
class ContactCard {
  const ContactCard({
    required this.kind,
    required this.name,
    this.avatarUrl,
    this.userId,
    this.username,
    this.circleId,
    this.memberCount,
    this.inviteCode,
  });

  static const attachmentKind = 'contact_card';

  /// The card of [attachment], or null when it is not a well-formed one.
  static ContactCard? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null || attachment['kind'] != attachmentKind) {
      return null;
    }
    final name = (attachment['name'] as String?)?.trim() ?? '';
    switch (attachment['card']) {
      case 'user':
        final userId = attachment['user_id'];
        if (userId is! String || userId.isEmpty) {
          return null;
        }
        return ContactCard(
          kind: ContactCardKind.user,
          name: name,
          avatarUrl: attachment['avatar_url'] as String?,
          userId: userId,
          username: attachment['username'] as String?,
        );
      case 'circle':
        final circleId = attachment['circle_id'];
        if (circleId is! String || circleId.isEmpty) {
          return null;
        }
        return ContactCard(
          kind: ContactCardKind.circle,
          name: name,
          avatarUrl: attachment['avatar_url'] as String?,
          circleId: circleId,
          memberCount: (attachment['member_count'] as num?)?.toInt(),
          inviteCode: attachment['invite_code'] as String?,
        );
    }
    return null;
  }

  final ContactCardKind kind;
  final String name;
  final String? avatarUrl;
  final String? userId;
  final String? username;
  final String? circleId;
  final int? memberCount;
  final String? inviteCode;

  bool get isUser => kind == ContactCardKind.user;

  /// What the card says under the name: "@ada" or "12 members".
  String? get subtitle {
    if (isUser) {
      final username = this.username?.trim() ?? '';
      return username.isEmpty ? null : '@$username';
    }
    final count = memberCount;
    if (count == null) {
      return null;
    }
    return count == 1
        ? tr('1 member')
        : tr('{count} members', {'count': count});
  }

  /// The name, or a plain word when the snapshot has none.
  String get displayName =>
      name.isEmpty ? (isUser ? tr('Someone') : tr('Circle')) : name;

  /// "Contact card: Ada", for screen readers.
  String get heading => tr('Contact card: {name}', {'name': displayName});
}

extension ContactCardMessage on ChatMessage {
  /// The contact card this message is, or null.
  ContactCard? get contactCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return ContactCard.maybeFromAttachment(attachment);
  }
}
