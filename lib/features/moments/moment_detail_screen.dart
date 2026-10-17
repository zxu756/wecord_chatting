import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/moments/moment_actions.dart';
import 'package:wecord/features/moments/moment_photo_viewer.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One Moment with all its comments and a box to write one. [replyToId]
/// starts a reply, [focusComment] puts the cursor in the box.
class MomentDetailScreen extends ConsumerStatefulWidget {
  const MomentDetailScreen({
    required this.postId,
    this.focusComment = false,
    this.replyToId,
    super.key,
  });

  final String postId;
  final bool focusComment;
  final String? replyToId;

  @override
  ConsumerState<MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends ConsumerState<MomentDetailScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  MomentComment? _replyTo;
  var _loading = true;
  var _sending = false;
  var _initialReplyResolved = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await ref.read(momentPostsStoreProvider.notifier).refresh(widget.postId);
    } on Object {
      // The post from the feed (if any) stays.
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _startReply(MomentComment comment) {
    final me = ref.read(momentsUserIdProvider);
    setState(() => _replyTo = comment.userId == me ? null : comment);
    _focus.requestFocus();
  }

  Future<void> _send(MomentPost post) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(momentPostsStoreProvider.notifier)
          .addComment(post.id, text, replyToCommentId: _replyTo?.id);
      if (mounted) {
        _input.clear();
        setState(() {
          _replyTo = null;
          _sending = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _sending = false);
        momentsFailureSnack(
          context,
          tr('Could not send the comment. Try again.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final myId = ref.watch(momentsUserIdProvider);
    final post = ref.watch(momentPostProvider(widget.postId));
    if (post != null && !_initialReplyResolved) {
      _initialReplyResolved = true;
      final replyId = widget.replyToId;
      if (replyId != null) {
        final target = post.comments.where((c) => c.id == replyId).firstOrNull;
        if (target != null && target.userId != myId) {
          _replyTo = target;
        }
      }
      if (widget.focusComment || widget.replyToId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focus.requestFocus();
          }
        });
      }
    }
    // A reply to a comment that has gone is just a comment.
    if (post != null &&
        _replyTo != null &&
        !post.comments.any((comment) => comment.id == _replyTo!.id)) {
      _replyTo = null;
    }

    final Widget body;
    if (post == null) {
      body = _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              key: const ValueKey('moment-gone'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr('This Moment is no longer available.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: c.muted),
                ),
              ),
            );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          MomentCard(
            post: post,
            myUserId: myId,
            onOpenAuthor: () =>
                context.push('${MomentsScreen.path}/of/${post.authorId}'),
            onOpenPhoto: (index) =>
                unawaited(openMomentPhotos(context, post.photos, index)),
            onComment: _focus.requestFocus,
            onReply: _startReply,
            onCommentMenu: (comment) => unawaited(
              showMomentCommentMenu(
                context,
                ref,
                post: post,
                comment: comment,
                myUserId: myId,
                onReply: _startReply,
              ),
            ),
            onLike: () => unawaited(toggleMomentLike(context, ref, post)),
            onDelete: () => unawaited(_delete(post)),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: c.paper,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(title: tr('Moment')),
                Expanded(child: body),
                if (post != null)
                  _CommentBar(
                    controller: _input,
                    focusNode: _focus,
                    replyTo: _replyTo,
                    sending: _sending,
                    onClearReply: () => setState(() => _replyTo = null),
                    onSend: () => unawaited(_send(post)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(MomentPost post) async {
    final deleted = await confirmDeleteMoment(context, ref, post);
    if (deleted && mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(MomentsScreen.path);
      }
    }
  }
}

/// The box under a Moment: an optional "Replying to" chip, the field and a
/// send button.
class _CommentBar extends StatelessWidget {
  const _CommentBar({
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.sending,
    required this.onClearReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final MomentComment? replyTo;
  final bool sending;
  final VoidCallback onClearReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final canSend = controller.text.trim().isNotEmpty && !sending;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        8,
        14,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (replyTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 16, color: c.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('Replying to {name}', {'name': replyTo!.name}),
                      key: const ValueKey('moment-replying-to'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.muted,
                      ),
                    ),
                  ),
                  WeCordIconButton(
                    key: const ValueKey('moment-reply-cancel'),
                    icon: Icons.close_rounded,
                    tooltip: tr('Cancel reply'),
                    variant: WeCordButtonVariant.ghost,
                    size: 28,
                    iconSize: 16,
                    onPressed: onClearReply,
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(WeCordRadii.xl),
                  ),
                  child: TextField(
                    key: const ValueKey('moment-comment-field'),
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: maxMomentCommentLength,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) => null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: TextStyle(fontSize: 15.5, color: c.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: replyTo == null
                          ? tr('Add a comment…')
                          : tr('Reply to {name}…', {'name': replyTo!.name}),
                      hintStyle: TextStyle(fontSize: 15.5, color: c.subtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              WeCordIconButton(
                key: const ValueKey('moment-comment-send'),
                icon: Icons.arrow_upward_rounded,
                tooltip: tr('Send comment'),
                variant: WeCordButtonVariant.accent,
                size: 44,
                onPressed: canSend ? onSend : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
