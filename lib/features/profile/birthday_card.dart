import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/home/phone_messages_panel.dart';
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The text a birthday card starts a chat with.
String birthdayGreeting() => tr('Happy birthday! 🎂');

/// "It's Ada's birthday today" in Notifications, with a button that opens the
/// chat with the greeting ready to send. It is there for the day only: the
/// list is asked for by calendar date.
class BirthdayCard extends ConsumerWidget {
  const BirthdayCard({required this.friend, super.key});

  final BirthdayFriend friend;

  Future<void> _wish(BuildContext context, WidgetRef ref) {
    final now = DateTime.now().toUtc();
    return openChatWithDraft(
      context,
      ref,
      friend: Profile(
        id: friend.userId,
        username: friend.username,
        displayName: friend.displayName,
        bio: '',
        createdAt: now,
        updatedAt: now,
        avatarUrl: friend.avatarUrl,
      ),
      text: birthdayGreeting(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final name = friend.displayName;
    return InboxCardShell(
      key: ValueKey('birthday-card-${friend.userId}'),
      onPressed: () => _wish(context, ref),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: name,
            avatarUrl: friend.avatarUrl,
            badge: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.panel, shape: BoxShape.circle),
              child: const Text('🎂', style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(text: tr('has a birthday today')),
                    ],
                  ),
                  style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: WeCordButton(
                    key: ValueKey('birthday-wish-${friend.userId}'),
                    label: tr('Send wishes'),
                    icon: Icons.cake_outlined,
                    size: WeCordButtonSize.small,
                    onPressed: () => _wish(context, ref),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
