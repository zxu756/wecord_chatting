import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/custom_status_label.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/profile_banner.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/report_user_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/profile_relationship.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens [userId]'s profile card as a sheet over the current page.
Future<void> showUserProfileSheet(BuildContext context, String userId) {
  return showWeCordSheet<void>(
    context,
    detents: const [0.5, 0.9],
    initialDetent: 0.9,
    builder: (context, scrollController) =>
        UserProfileView(userId: userId, scrollController: scrollController),
  );
}

/// Someone's profile (`/profile/:userId`) as a page: the profile card with
/// a back button over its banner.
class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({required this.userId, super.key});

  static const path = '/profile';

  final String userId;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final router = GoRouter.maybeOf(context);
    final VoidCallback? back = canPop
        ? () => Navigator.of(context).maybePop()
        : (!wide && router != null ? () => router.go('/home') : null);
    return Scaffold(
      backgroundColor: wide ? c.paper : c.panel,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              margin: wide ? const EdgeInsets.only(top: 24) : null,
              decoration: wide
                  ? BoxDecoration(
                      color: c.panel,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(WeCordRadii.xxl),
                      ),
                    )
                  : null,
              clipBehavior: wide ? Clip.antiAlias : Clip.none,
              child: Stack(
                children: [
                  UserProfileView(userId: userId),
                  if (back != null)
                    Positioned(
                      top: 18,
                      left: 18,
                      child: WeCordIconButton(
                        key: const ValueKey('profile-back'),
                        icon: Icons.chevron_left_rounded,
                        tooltip: tr('Back'),
                        variant: WeCordButtonVariant.onPaper,
                        size: 36,
                        iconSize: 22,
                        onPressed: back,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The profile card: banner, avatar with presence, status pill, name,
/// tag, @username and pronouns, the actions, about, what is shared and
/// when they joined.
class UserProfileView extends ConsumerStatefulWidget {
  const UserProfileView({
    required this.userId,
    this.scrollController,
    super.key,
  });

  final String userId;
  final ScrollController? scrollController;

  @override
  ConsumerState<UserProfileView> createState() => _UserProfileViewState();
}

class _UserProfileViewState extends ConsumerState<UserProfileView> {
  late Future<ProfileSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(UserProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _reload();
    }
  }

  void _reload() {
    _summaryFuture = ref
        .read(profileRepositoryProvider)
        .getProfileSummary(widget.userId);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        setState(_reload);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Could not update profile action. Try again.')),
        ),
      );
    }
  }

  Future<void> _openConversation(Profile profile) async {
    try {
      final conversationId = await ref
          .read(chatsRepositoryProvider)
          .getOrCreateDirectConversation(profile.id);
      if (!mounted) {
        return;
      }
      openPage(
        context,
        '${ChatsScreen.path}/$conversationId',
        extra: ChatThreadRouteExtra(
          title: profile.displayLabel,
          type: ConversationType.direct,
          avatarUrl: profile.avatarUrl,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not start chat. Try again.'))),
      );
    }
  }

  Future<void> _showMore(ProfileSummary summary) async {
    final profile = summary.profile;
    final blocked =
        summary.relationshipStatus == ProfileRelationshipStatus.blocked;
    await showWeCordSheet<void>(
      context,
      title: profile.displayLabel,
      builder: (sheetContext, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SettingsGroup(
            color: sheetContext.tokens.colors.well,
            children: [
              if (blocked)
                SettingsRow(
                  key: const ValueKey('profile-unblock'),
                  icon: Icons.lock_open_outlined,
                  title: tr('Unblock'),
                  showChevron: false,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _run(
                      () => ref
                          .read(profileRepositoryProvider)
                          .unblockUser(profile.id),
                    );
                  },
                )
              else
                SettingsRow(
                  key: const ValueKey('profile-block'),
                  icon: Icons.block_rounded,
                  title: tr('Block'),
                  destructive: true,
                  showChevron: false,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _run(
                      () => ref
                          .read(profileRepositoryProvider)
                          .blockUser(profile.id),
                    );
                  },
                ),
              SettingsRow(
                key: const ValueKey('profile-report'),
                icon: Icons.flag_outlined,
                tone: SettingsTone.warning,
                title: tr('Report'),
                showChevron: false,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showReportUserSheet(context, profile);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return FutureBuilder<ProfileSummary>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: WeCordButton(
              label: tr('Try again'),
              onPressed: () => setState(_reload),
            ),
          );
        }

        final summary = snapshot.data!;
        final profile = summary.profile;
        final onlineIds =
            ref.watch(onlineUserIdsProvider).value ?? const <String>{};
        final presence = presenceOf(
          profile.id,
          onlineUserIds: onlineIds,
          statuses: ref.watch(presenceStatusesProvider).value,
        );
        final status = activeCustomStatus(profile.customStatus);
        final isSelf =
            summary.relationshipStatus == ProfileRelationshipStatus.self;

        return ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(
            10,
            10,
            10,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            ProfileBannerHeader(
              bannerUrl: profile.bannerUrl,
              colorSeed: profile.displayLabel,
              avatarSize: 84,
              avatar: ProfileAvatar(
                name: profile.displayLabel,
                avatarUrl: profile.avatarUrl,
                size: 84,
                presence:
                    presence == null || presence == PresenceStatus.invisible
                    ? null
                    : presenceColor(context, presence),
              ),
              trailing: status == null
                  ? null
                  : Container(
                      key: const ValueKey('profile-status-pill'),
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: c.raised,
                        shape: const StadiumBorder(),
                      ),
                      child: CustomStatusLabel(
                        status: profile.customStatus,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.displayLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: c.ink,
                          ),
                        ),
                      ),
                      ProfileNameBadges(userId: profile.id, leadingGap: 8),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ['@${profile.username}', ?profile.pronouns].join(' · '),
                    key: const ValueKey('profile-username-line'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                  if (!isSelf) ...[
                    const SizedBox(height: 16),
                    _ProfileActions(
                      summary: summary,
                      onMessage: () => _openConversation(profile),
                      onAddFriend: () => _run(
                        () => ref
                            .read(contactsRepositoryProvider)
                            .sendFriendRequest(profile.id),
                      ),
                      onAcceptRequest: () => _run(
                        () => ref
                            .read(contactsRepositoryProvider)
                            .acceptFriendRequest(summary.incomingRequestId!),
                      ),
                      onMore: () => _showMore(summary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (profile.bio.isNotEmpty) ...[
                    _Block(
                      key: const ValueKey('profile-about'),
                      title: tr('About me'),
                      child: Text(
                        profile.bio,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.55,
                          color: c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (summary.mutualCircles.isNotEmpty) ...[
                    _Block(
                      key: const ValueKey('mutual-circles'),
                      title: summary.mutualCircles.length == 1
                          ? tr('1 mutual circle')
                          : tr('{count} mutual circles', {
                              'count': summary.mutualCircles.length,
                            }),
                      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                      child: Column(
                        children: [
                          for (final circle in summary.mutualCircles)
                            _MutualRow(
                              leading: StoredThingAvatar(
                                label: circle.name,
                                avatarUrl: circle.avatarUrl,
                                size: 34,
                                radius: 11,
                              ),
                              title: circle.name,
                              onPressed: () =>
                                  openPage(context, circleLocation(circle.id)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (summary.mutualFriends.isNotEmpty) ...[
                    _Block(
                      key: const ValueKey('mutual-friends'),
                      title: summary.mutualFriends.length == 1
                          ? tr('1 mutual friend')
                          : tr('{count} mutual friends', {
                              'count': summary.mutualFriends.length,
                            }),
                      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                      child: Column(
                        children: [
                          for (final friend in summary.mutualFriends)
                            _MutualRow(
                              leading: ProfileAvatar(
                                name: friend.label,
                                avatarUrl: friend.avatarUrl,
                                size: 34,
                              ),
                              title: friend.label,
                              subtitle: '@${friend.username}',
                              onPressed: () => context.push(
                                '${UserProfileScreen.path}/${friend.id}',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _JoinedBlock(createdAt: profile.createdAt),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A quiet rounded block of the profile card with a small header.
class _Block extends StatelessWidget {
  const _Block({
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final insetHeader = padding.horizontal < 20;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(insetHeader ? 8 : 0, 0, 0, 8),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.subtle,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _MutualRow extends StatelessWidget {
  const _MutualRow({
    required this.leading,
    required this.title,
    required this.onPressed,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      pressedScale: 0.98,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: hovered
                ? c.ink.withValues(alpha: 0.04)
                : c.ink.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
            ],
          ),
        );
      },
    );
  }
}

class _JoinedBlock extends StatelessWidget {
  const _JoinedBlock({required this.createdAt});

  final DateTime createdAt;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final local = createdAt.toLocal();
    final date = AppStrings.isChinese
        ? '${local.year} 年 ${local.month} 月'
        : '${_months[local.month - 1]} ${local.year}';
    return Container(
      key: const ValueKey('profile-joined'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr('Joined WeCord'),
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
          Text(
            date,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Message (or Add Friend / Accept Request) as the wide ink button, with
/// round-cornered square buttons for the other actions and More.
class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.summary,
    required this.onMessage,
    required this.onAddFriend,
    required this.onAcceptRequest,
    required this.onMore,
  });

  final ProfileSummary summary;
  final VoidCallback onMessage;
  final VoidCallback onAddFriend;
  final VoidCallback onAcceptRequest;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final primary = summary.canStartChat
        ? _ActionButton(
            key: const ValueKey('profile-message'),
            icon: Icons.chat_bubble_outline_rounded,
            label: tr('Message'),
            primary: true,
            onPressed: onMessage,
          )
        : summary.canAcceptRequest
        ? _ActionButton(
            key: const ValueKey('profile-accept-request'),
            icon: Icons.check_rounded,
            label: tr('Accept Request'),
            primary: true,
            onPressed: onAcceptRequest,
          )
        : summary.canSendFriendRequest
        ? _ActionButton(
            key: const ValueKey('profile-add-friend'),
            icon: Icons.person_add_alt_1_outlined,
            label: tr('Add Friend'),
            primary: true,
            onPressed: onAddFriend,
          )
        : null;
    final pending =
        summary.relationshipStatus == ProfileRelationshipStatus.outgoingRequest;
    final bot = summary.relationshipStatus == ProfileRelationshipStatus.bot;
    return Row(
      children: [
        if (primary != null)
          Expanded(child: primary)
        else
          Expanded(
            child: _ActionButton(
              key: bot ? const ValueKey('profile-bot') : null,
              icon: bot
                  ? Icons.smart_toy_outlined
                  : pending
                  ? Icons.schedule_rounded
                  : Icons.do_not_disturb_on_outlined,
              label: bot
                  ? tr('Bot account')
                  : pending
                  ? tr('Request sent')
                  : tr('Blocked'),
              onPressed: null,
            ),
          ),
        const SizedBox(width: 8),
        _ActionButton(
          key: const ValueKey('profile-more'),
          icon: Icons.more_horiz_rounded,
          tooltip: tr('More'),
          onPressed: onMore,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onPressed,
    this.label,
    this.tooltip,
    this.primary = false,
    super.key,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final fill = primary ? c.ink : c.raised;
    final foreground = primary ? c.onInk : c.ink;
    final label = this.label;
    return WeCordPressable(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered =
            onPressed != null &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          height: 48,
          width: label == null ? 48 : null,
          padding: label == null
              ? null
              : const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(
                    (primary ? c.onInk : c.ink).withValues(alpha: 0.08),
                    fill,
                  )
                : fill,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 19,
                color: onPressed == null ? c.muted : foreground,
              ),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: onPressed == null ? c.muted : foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
