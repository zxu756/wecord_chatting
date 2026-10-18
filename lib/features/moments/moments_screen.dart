import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/moments/moment_actions.dart';
import 'package:wecord/features/moments/moment_composer_screen.dart';
import 'package:wecord/features/moments/moment_photo_viewer.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_new_pill.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Moments (朋友圈): the feed of friends' posts with the person's cover,
/// avatar and name on top, newest first with pages loaded as they scroll.
/// With [userId] it is that friend's page instead.
class MomentsScreen extends ConsumerStatefulWidget {
  const MomentsScreen({this.userId, super.key});

  static const path = '/moments';

  /// A friend's page; null for the feed.
  final String? userId;

  @override
  ConsumerState<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends ConsumerState<MomentsScreen> {
  final _scroll = ScrollController();

  NotifierProvider<MomentsFeedController, MomentsFeedState> get _provider =>
      widget.userId == null
      ? momentsFeedProvider
      : momentsPageProvider(widget.userId!);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.userId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Opening Moments clears the badge on its entry.
  Future<void> _markSeen() async {
    try {
      await ref.read(momentsRepositoryProvider).markSeen();
    } on Object {
      return;
    }
    if (mounted) {
      ref.invalidate(momentsUnseenProvider);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 600) {
      unawaited(ref.read(_provider.notifier).loadMore());
    }
  }

  Future<void> _refresh() async {
    await ref.read(_provider.notifier).refresh();
    if (widget.userId == null) {
      unawaited(_markSeen());
    }
    ref
      ..invalidate(momentsProfileProvider)
      ..invalidate(momentNotificationsProvider);
  }

  /// "N new posts": back to the top with them in.
  Future<void> _showNew() async {
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: WeCordMotion.smooth.durationOf(context),
          curve: WeCordMotion.standard,
        ),
      );
    }
    await ref.read(_provider.notifier).showNew();
    if (widget.userId == null) {
      unawaited(_markSeen());
    }
  }

  Future<void> _changeCover() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final bytes = await ref.read(momentPhotoPickerProvider).pickCover();
      if (bytes == null) {
        return;
      }
      await ref.read(momentsRepositoryProvider).setCover(bytes);
      ref
        ..invalidate(momentsProfileProvider)
        ..invalidate(momentsSettingsProvider);
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not change the cover. Try again.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final myId = ref.watch(momentsUserIdProvider);
    final profileId = widget.userId ?? myId;
    final feed = ref.watch(_provider);
    final posts = ref.watch(momentPostsStoreProvider);
    final unread = ref.watch(momentNotificationsUnreadProvider);
    final isMine = profileId != null && profileId == myId;
    final profile = profileId == null
        ? null
        : ref.watch(momentsProfileProvider(profileId)).value;
    final ids = [
      for (final id in feed.ids)
        if (posts.containsKey(id)) id,
    ];

    Widget body;
    if (feed.loading && ids.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (feed.failed && ids.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('Could not load Moments.'),
              style: TextStyle(color: c.dangerText),
            ),
            const SizedBox(height: 12),
            WeCordButton(
              key: const ValueKey('moments-retry'),
              label: tr('Try again'),
              onPressed: _refresh,
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const ValueKey('moments-list'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: MomentsCoverHeader(
                  name: profile?.name ?? '',
                  avatarUrl: profile?.avatarUrl,
                  coverPath: profile?.coverPath,
                  isMine: isMine,
                  onChangeCover: _changeCover,
                  onOpenAvatar: widget.userId == null && myId != null
                      ? () => context.push('${MomentsScreen.path}/of/$myId')
                      : null,
                ),
              ),
            ),
            if (widget.userId == null && unread > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _UnreadPill(count: unread),
                ),
              ),
            if (ids.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyMoments(
                  feed: widget.userId == null,
                  name: profile?.name ?? '',
                  canPost: isMine || widget.userId == null,
                ),
              )
            else
              SliverList.separated(
                itemCount: ids.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final post = posts[ids[index]]!;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MomentCard(
                      post: post,
                      myUserId: myId,
                      maxComments: 3,
                      onOpen: () => _openDetail(post),
                      onOpenAuthor: () => _openAuthor(post),
                      onOpenPhoto: (index) => unawaited(
                        openMomentPhotos(context, post.photos, index),
                      ),
                      onComment: () => _openDetail(post, focusComment: true),
                      onReply: (comment) => _openDetail(post, replyTo: comment),
                      onCommentMenu: (comment) => unawaited(
                        showMomentCommentMenu(
                          context,
                          ref,
                          post: post,
                          comment: comment,
                          myUserId: myId,
                          onReply: (comment) =>
                              _openDetail(post, replyTo: comment),
                        ),
                      ),
                      onLike: () =>
                          unawaited(toggleMomentLike(context, ref, post)),
                      onDelete: () => unawaited(_delete(post)),
                    ),
                  );
                },
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  32 + MediaQuery.paddingOf(context).bottom,
                ),
                child: feed.loadingMore
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : feed.moreFailed
                    ? Center(
                        child: WeCordButton(
                          label: tr('Try again'),
                          variant: WeCordButtonVariant.secondary,
                          size: WeCordButtonSize.small,
                          onPressed: () => unawaited(
                            ref.read(_provider.notifier).loadMore(),
                          ),
                        ),
                      )
                    : !feed.hasMore && ids.length > 3
                    ? Center(
                        child: Text(
                          tr("You're all caught up"),
                          style: TextStyle(fontSize: 13, color: c.subtle),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: widget.userId == null || isMine
                      ? tr('Moments')
                      : tr("{name}'s Moments", {'name': profile?.name ?? ''}),
                  actions: [
                    if (widget.userId == null || isMine)
                      WeCordIconButton(
                        key: const ValueKey('moments-compose'),
                        icon: Icons.add_a_photo_outlined,
                        tooltip: tr('New Moment'),
                        variant: WeCordButtonVariant.accent,
                        onPressed: () =>
                            context.push(MomentComposerScreen.path),
                      ),
                  ],
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: body),
                      if (feed.newIds.isNotEmpty)
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: NewMomentsPill(
                              count: feed.newIds.length,
                              onPressed: () => unawaited(_showNew()),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDetail(
    MomentPost post, {
    bool focusComment = false,
    MomentComment? replyTo,
  }) {
    final query = {
      if (focusComment) 'comment': '1',
      if (replyTo != null) 'reply': replyTo.id,
    };
    context.push(
      Uri(
        path: '${MomentsScreen.path}/${post.id}',
        queryParameters: query.isEmpty ? null : query,
      ).toString(),
    );
  }

  void _openAuthor(MomentPost post) {
    if (widget.userId == post.authorId) {
      return;
    }
    context.push('${MomentsScreen.path}/of/${post.authorId}');
  }

  Future<void> _delete(MomentPost post) async {
    final deleted = await confirmDeleteMoment(context, ref, post);
    if (deleted && mounted) {
      ref.read(_provider.notifier).removeId(post.id);
    }
  }
}

/// The top of the page: the cover picture (or a soft color) with the
/// person's avatar and name on it.
class MomentsCoverHeader extends ConsumerWidget {
  const MomentsCoverHeader({
    required this.name,
    required this.avatarUrl,
    required this.coverPath,
    required this.isMine,
    required this.onChangeCover,
    this.onOpenAvatar,
    super.key,
  });

  final String name;
  final String? avatarUrl;
  final String? coverPath;
  final bool isMine;
  final VoidCallback onChangeCover;

  /// Opens the person's own page.
  final VoidCallback? onOpenAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final fill = WeCordAvatarColors.forSeed(name);
    final radius = BorderRadius.circular(WeCordRadii.xl);
    return Semantics(
      container: true,
      label: isMine ? tr('Your cover') : tr('Cover of {name}', {'name': name}),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: fill),
                  if (coverPath == null)
                    const CustomPaint(painter: _CoverLightsPainter())
                  else
                    MomentImage(path: coverPath!),
                  // Keeps the name readable on any picture.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.45, 1],
                        colors: [Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(
                children: [
                  WeCordPressable(
                    key: const ValueKey('moments-cover-avatar'),
                    onPressed: onOpenAvatar,
                    pressedScale: 0.96,
                    semanticLabel: onOpenAvatar == null
                        ? null
                        : tr('My Moments'),
                    shape: const CircleBorder(),
                    builder: (context, states) => Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: c.panel,
                        shape: BoxShape.circle,
                      ),
                      child: ProfileAvatar(
                        name: name,
                        avatarUrl: avatarUrl,
                        size: 52,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      key: const ValueKey('moments-cover-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isMine)
              Positioned(
                top: 10,
                right: 10,
                child: WeCordIconButton(
                  key: const ValueKey('moments-change-cover'),
                  icon: Icons.photo_camera_outlined,
                  tooltip: tr('Change cover'),
                  size: 38,
                  iconSize: 19,
                  onPressed: onChangeCover,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoverLightsPainter extends CustomPainter {
  const _CoverLightsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.2),
      70,
      Paint()..color = Colors.white.withValues(alpha: 0.26),
    );
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.9),
      110,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(_CoverLightsPainter oldDelegate) => false;
}

/// "3 new likes and comments", opening Notifications.
class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Align(
      alignment: Alignment.center,
      child: WeCordPressable(
        key: const ValueKey('moments-unread-pill'),
        onPressed: () => context.push(InboxScreen.path),
        builder: (context, states) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: ShapeDecoration(
            color: c.accentSoft,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, size: 16, color: c.accentText),
              const SizedBox(width: 8),
              Text(
                count == 1
                    ? tr('1 new like or comment')
                    : tr('{count} new likes and comments', {'count': count}),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: c.accentText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMoments extends StatelessWidget {
  const _EmptyMoments({
    required this.feed,
    required this.name,
    required this.canPost,
  });

  final bool feed;
  final String name;
  final bool canPost;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('moments-empty'),
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SettingsIconTile(
            icon: Icons.auto_awesome_motion_outlined,
            tone: SettingsTone.accent,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            feed ? tr('No Moments yet') : tr('Nothing to see here yet'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            feed
                ? tr('Share a photo or a thought with your friends.')
                : tr('{name} has not shared anything with you.', {
                    'name': name,
                  }),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
          ),
          if (feed && canPost) ...[
            const SizedBox(height: 18),
            WeCordButton(
              key: const ValueKey('moments-empty-post'),
              label: tr('Post a Moment'),
              icon: Icons.add_a_photo_outlined,
              onPressed: () => context.push(MomentComposerScreen.path),
            ),
          ],
        ],
      ),
    );
  }
}
