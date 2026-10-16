import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile_relationship.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The other person's profile summary, for the panel beside a direct chat.
final chatProfileSummaryProvider = FutureProvider.autoDispose
    .family<ProfileSummary, String>((ref, userId) {
      return ref.read(profileRepositoryProvider).getProfileSummary(userId);
    });

/// The right panel of a desktop direct chat (design C-desk-chat): a color
/// banner, the big avatar, name and handle, then About me and the circles
/// you share, on the sidebar color. Fills the width it gets (the chat
/// resizes it).
class ChatProfilePanel extends ConsumerWidget {
  const ChatProfilePanel({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.presence,
    super.key,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final Color? presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final summary = ref.watch(chatProfileSummaryProvider(userId)).value;
    final profile = summary?.profile;
    final displayName = profile?.displayLabel.trim().isNotEmpty == true
        ? profile!.displayLabel
        : name;
    final handle = [
      if (profile != null) '@${profile.username}',
      ?profile?.pronouns,
    ].join(' · ');
    final bio = profile?.bio.trim() ?? '';
    final circles = summary?.mutualCircles ?? const <MutualCircle>[];

    Widget block(String title, Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.subtle,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    return Container(
      key: const ValueKey('chat-profile-panel'),
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(left: BorderSide(color: c.lineSoft)),
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                height: 110,
                decoration: BoxDecoration(
                  color: WeCordAvatarColors.forSeed(name),
                  borderRadius: BorderRadius.circular(18),
                  image: profile?.bannerUrl == null
                      ? null
                      : DecorationImage(
                          image: NetworkImage(profile!.bannerUrl!),
                          fit: BoxFit.cover,
                          onError: (_, _) {},
                        ),
                ),
              ),
              Positioned(
                left: 18,
                top: 70,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: c.sidebar,
                    shape: BoxShape.circle,
                  ),
                  child: ChatAvatar(
                    name: displayName,
                    avatarUrl: avatarUrl ?? profile?.avatarUrl,
                    size: 80,
                    presence: presence,
                    ringColor: c.sidebar,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: c.ink,
                  ),
                ),
                if (handle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      handle,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                const SizedBox(height: 14),
                if (bio.isNotEmpty) ...[
                  block(
                    tr('About me'),
                    Text(
                      bio,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (circles.isNotEmpty) ...[
                  block(
                    tr('Mutual circles · {count}', {'count': circles.length}),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final circle in circles)
                          Tooltip(
                            message: circle.name,
                            child: ThingAvatar(label: circle.name, size: 32),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                WeCordButton(
                  label: tr('View profile'),
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  expand: true,
                  onPressed: () =>
                      context.push('${UserProfileScreen.path}/$userId'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
