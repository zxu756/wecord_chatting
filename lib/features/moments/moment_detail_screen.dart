import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/accessibility/image_alt_sheet.dart';
import 'package:wecord/features/moments/moment_actions.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moment_photo_viewer.dart';
import 'package:wecord/features/moments/moment_share.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/features/stickers/my_stickers_panel.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
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
  MomentCommentPicture? _picture;
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

  /// Offers the person's stickers or a photo for the comment.
  Future<void> _attach() async {
    final choice = await showWeCordSheet<String>(
      context,
      title: tr('Add a picture or sticker'),
      builder: (sheetContext, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SettingsGroup(
            color: sheetContext.tokens.colors.well,
            children: [
              SettingsRow(
                key: const ValueKey('comment-attach-sticker'),
                icon: Icons.emoji_emotions_outlined,
                title: tr('My stickers'),
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('sticker'),
              ),
              SettingsRow(
                key: const ValueKey('comment-attach-photo'),
                icon: Icons.photo_outlined,
                title: tr('Photo'),
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('photo'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    try {
      if (choice == 'photo') {
        final picked = await ref
            .read(momentPhotoPickerProvider)
            .pickCommentPhoto();
        if (picked != null && mounted) {
          setState(() => _picture = picked);
        }
        return;
      }
      final sticker = await showWeCordSheet<UserSticker>(
        context,
        title: tr('My stickers'),
        builder: (sheetContext, _) => MyStickersPanel(
          onPick: (sticker) => Navigator.of(sheetContext).pop(sticker),
        ),
      );
      if (sticker == null || !mounted) {
        return;
      }
      final bytes = await ref
          .read(userStickersRepositoryProvider)
          .download(StickerFile(userStickerBucket, sticker.path));
      if (mounted) {
        setState(
          () => _picture = MomentCommentPicture(
            bytes: bytes,
            extension: sticker.extension,
            width: sticker.width,
            height: sticker.height,
            sticker: true,
          ),
        );
      }
    } on Object {
      if (mounted) {
        momentsFailureSnack(
          context,
          tr('Could not use that picture. Try another.'),
        );
      }
    }
  }

  Future<void> _describePicture() async {
    final picture = _picture;
    if (picture == null) {
      return;
    }
    final result = await showImageAltSheet(
      context,
      pictures: [
        AltPicture(id: 'comment', picture: picture.bytes, current: picture.alt),
      ],
    );
    if (result != null && mounted) {
      setState(() => _picture = picture.withAlt(result['comment']));
    }
  }

  Future<void> _send(MomentPost post) async {
    final text = _input.text.trim();
    final picture = _picture;
    if ((text.isEmpty && picture == null) || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(momentPostsStoreProvider.notifier)
          .addComment(
            post.id,
            text,
            replyToCommentId: _replyTo?.id,
            picture: picture,
          );
      if (mounted) {
        _input.clear();
        setState(() {
          _replyTo = null;
          _picture = null;
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
            onShare: () => unawaited(showMomentSharePicker(context, post.id)),
            onTogglePin: post.authorId == myId
                ? () => unawaited(toggleMomentPin(context, ref, post))
                : null,
            showPinned: true,
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
                    picture: _picture,
                    sending: _sending,
                    onClearReply: () => setState(() => _replyTo = null),
                    onAttach: () => unawaited(_attach()),
                    onDescribe: () => unawaited(_describePicture()),
                    onRemovePicture: () => setState(() => _picture = null),
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
    required this.picture,
    required this.sending,
    required this.onClearReply,
    required this.onAttach,
    required this.onDescribe,
    required this.onRemovePicture,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final MomentComment? replyTo;
  final MomentCommentPicture? picture;
  final bool sending;
  final VoidCallback onClearReply;
  final VoidCallback onAttach;
  final VoidCallback onDescribe;
  final VoidCallback onRemovePicture;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final canSend =
        (controller.text.trim().isNotEmpty || picture != null) && !sending;
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
          if (picture != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PicturePreview(
                picture: picture!,
                onDescribe: onDescribe,
                onRemove: onRemovePicture,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              WeCordIconButton(
                key: const ValueKey('moment-comment-attach'),
                icon: Icons.add_photo_alternate_outlined,
                tooltip: tr('Add a picture or sticker'),
                variant: WeCordButtonVariant.ghost,
                size: 44,
                onPressed: sending ? null : onAttach,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
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

/// The picture or sticker waiting to be sent with the comment: a small view
/// of it, a way to describe it and a way to take it off.
class _PicturePreview extends StatelessWidget {
  const _PicturePreview({
    required this.picture,
    required this.onDescribe,
    required this.onRemove,
  });

  final MomentCommentPicture picture;
  final VoidCallback onDescribe;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final alt = picture.alt;
    return Container(
      key: const ValueKey('moment-comment-picture'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WeCordRadii.sm),
              child: Image.memory(
                picture.bytes,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 52, height: 52),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: WeCordPressable(
              key: const ValueKey('moment-comment-picture-describe'),
              onPressed: onDescribe,
              pressedScale: 1,
              semanticLabel: alt == null
                  ? tr('Describe picture')
                  : tr('Described: {description}', {'description': alt}),
              excludeSemantics: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.sm),
              ),
              builder: (context, states) => Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(
                      Icons.short_text_rounded,
                      size: 18,
                      color: alt == null ? c.muted : c.accentText,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        alt ?? tr('Describe picture'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: alt == null ? c.muted : c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          WeCordIconButton(
            key: const ValueKey('moment-comment-picture-remove'),
            icon: Icons.close_rounded,
            tooltip: tr('Remove picture'),
            variant: WeCordButtonVariant.ghost,
            size: 36,
            iconSize: 18,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
