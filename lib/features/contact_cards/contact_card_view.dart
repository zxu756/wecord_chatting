import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/contact_cards/contact_card_models.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens what [card] points at: a person's profile (with Add friend or
/// Message, as everywhere; what it shows follows their profile visibility
/// and blocks), or the circle's invite page with its preview and Join.
Future<void> openContactCard(BuildContext context, ContactCard card) async {
  final userId = card.userId;
  if (card.isUser && userId != null) {
    await showUserProfileSheet(context, userId, source: FriendSource.card);
    return;
  }
  final code = card.inviteCode;
  if (code != null && code.isNotEmpty) {
    await GoRouter.of(context).push<void>(circleInvitePath(code));
  }
}

/// A contact card in a chat: avatar, name and @username (or member count),
/// and what it is. A tap opens the profile or the circle's invite.
class ContactCardView extends StatelessWidget {
  const ContactCardView({required this.card, this.onOpen, super.key});

  final ContactCard card;

  /// Opens the card; by default [openContactCard].
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final subtitle = card.subtitle;
    final kindLabel = card.isUser ? tr('Contact card') : tr('Circle invite');
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 260.0,
          260.0,
        );
        return SizedBox(
          width: width,
          child: WeCordPressable(
            key: ValueKey('contact-card-${card.userId ?? card.circleId}'),
            onPressed:
                onOpen ?? () => unawaited(openContactCard(context, card)),
            semanticLabel: [
              card.heading,
              ?subtitle,
              if (!card.isUser) kindLabel,
            ].join(', '),
            hint: card.isUser
                ? tr('Opens the profile')
                : tr('Opens the circle invite'),
            mergeSemantics: false,
            pressedScale: 0.99,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            builder: (context, states) => Container(
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
                border: Border.all(
                  color: states.contains(WidgetState.hovered)
                      ? c.faint
                      : c.line,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: ChatAvatar(
                          name: card.displayName,
                          avatarUrl: card.avatarUrl,
                          size: 48,
                          thing: !card.isUser,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              card.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: c.lineSoft),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          card.isUser
                              ? Icons.person_outline_rounded
                              : Icons.groups_2_outlined,
                          size: 14,
                          color: c.subtle,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            kindLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: c.subtle,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: c.faint,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
