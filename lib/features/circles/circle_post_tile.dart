import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_event_editor_sheet.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/report_reason.dart';
import 'package:wecord/shared/ui/ui.dart';

enum _PostAction { delete, report }

class CirclePostTile extends ConsumerWidget {
  const CirclePostTile({
    required this.post,
    required this.onChanged,
    super.key,
  });

  final CirclePost post;
  final VoidCallback onChanged;

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    Offset? position,
  ) async {
    final canDelete = post.isOwnPost || post.canManagePost;
    final action = await showCircleActionMenu<_PostAction>(
      context,
      position: position,
      items: [
        if (canDelete)
          CircleMenuItem(
            value: _PostAction.delete,
            icon: Icons.delete_outline_rounded,
            label: tr('Delete'),
            destructive: true,
          )
        else
          CircleMenuItem(
            value: _PostAction.report,
            icon: Icons.flag_outlined,
            label: tr('Report'),
            destructive: true,
          ),
      ],
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case _PostAction.delete:
        await _deletePost(context, ref);
      case _PostAction.report:
        await showCirclePostReportSheet(
          context,
          post: post,
          onReported: onChanged,
        );
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleNetworkAvatar(
                name: post.author.displayLabel,
                url: post.author.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      _formatPostTime(post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.subtle,
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (buttonContext) => WeCordIconButton(
                  tooltip: tr('Post actions'),
                  icon: Icons.more_horiz_rounded,
                  variant: WeCordButtonVariant.ghost,
                  size: 36,
                  onPressed: () {
                    final box = buttonContext.findRenderObject() as RenderBox?;
                    _showActions(
                      context,
                      ref,
                      box?.localToGlobal(box.size.bottomRight(Offset.zero)),
                    );
                  },
                ),
              ),
            ],
          ),
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                post.body,
                style: TextStyle(fontSize: 15, height: 1.45, color: c.ink),
              ),
            ),
          ],
          if (post.imageAttachment != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _PostImagePreview(attachment: post.imageAttachment!),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _PostActionPill(
                tooltip: post.likedByCurrentUser
                    ? tr('Unlike post')
                    : tr('Like post'),
                icon: post.likedByCurrentUser
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: '${post.likeCount}',
                active: post.likedByCurrentUser,
                onPressed: () => _toggleLike(ref),
              ),
              const SizedBox(width: 6),
              _PostActionPill(
                tooltip: tr('Comment'),
                icon: Icons.mode_comment_outlined,
                label: '${post.commentCount}',
                onPressed: () => showCirclePostCommentSheet(
                  context,
                  post: post,
                  onCommented: onChanged,
                ),
              ),
            ],
          ),
          if (post.comments.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final comment in post.comments.take(2))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${comment.author.displayLabel}: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: comment.body),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: c.ink,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleLike(WidgetRef ref) async {
    await ref
        .read(circlesRepositoryProvider)
        .togglePostLike(postId: post.id, liked: !post.likedByCurrentUser);
    onChanged();
  }

  Future<void> _deletePost(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(circlesRepositoryProvider).deletePost(post.id);
      onChanged();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Could not delete post. Try again.'))),
        );
      }
    }
  }
}

/// Like and comment under a post: an icon and a count in a soft pill,
/// accent while [active].
class _PostActionPill extends StatelessWidget {
  const _PostActionPill({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final foreground = active ? c.accentText : c.muted;
    return WeCordPressable(
      tooltip: tooltip,
      semanticLabel: '$tooltip, $label',
      onPressed: onPressed,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: usesTouchInput(context) ? minTouchTargetSize : 32,
          ),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: WeCordMotion.quick,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: ShapeDecoration(
                color: active
                    ? c.accentSoft
                    : hovered
                    ? c.raised
                    : c.raised.withValues(alpha: 0),
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: foreground,
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

class _PostImagePreview extends ConsumerWidget {
  const _PostImagePreview({required this.attachment});

  final ImageAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(circlesRepositoryProvider).createImageUrl(attachment);
    return FutureBuilder<String>(
      future: url,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          child: Image.network(
            snapshot.data!,
            height: 220,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

Future<void> showCirclePostCommentSheet(
  BuildContext context, {
  required CirclePost post,
  required VoidCallback onCommented,
}) {
  return showCircleFormSheet<void>(
    context,
    builder: (_) =>
        _CirclePostCommentSheet(post: post, onCommented: onCommented),
  );
}

class _CirclePostCommentSheet extends ConsumerStatefulWidget {
  const _CirclePostCommentSheet({
    required this.post,
    required this.onCommented,
  });

  final CirclePost post;
  final VoidCallback onCommented;

  @override
  ConsumerState<_CirclePostCommentSheet> createState() =>
      _CirclePostCommentSheetState();
}

class _CirclePostCommentSheetState
    extends ConsumerState<_CirclePostCommentSheet> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _controller.text.trim();
    if (_isSubmitting || body.isEmpty) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await ref
          .read(circlesRepositoryProvider)
          .createComment(postId: widget.post.id, body: body);
      widget.onCommented();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorText = tr('Could not comment. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleFormBody(
      title: tr('Comment'),
      errorText: _errorText,
      actions: [
        WeCordButton(
          label: _isSubmitting ? tr('Commenting...') : tr('Comment'),
          expand: true,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
      children: [
        WeCordTextField(
          controller: _controller,
          enabled: !_isSubmitting,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          hint: tr('Write a comment'),
          inputFormatters: [LengthLimitingTextInputFormatter(1000)],
        ),
      ],
    );
  }
}

Future<void> showCirclePostReportSheet(
  BuildContext context, {
  required CirclePost post,
  required VoidCallback onReported,
}) {
  return showCircleFormSheet<void>(
    context,
    builder: (_) => _CirclePostReportSheet(post: post, onReported: onReported),
  );
}

class _CirclePostReportSheet extends ConsumerStatefulWidget {
  const _CirclePostReportSheet({required this.post, required this.onReported});

  final CirclePost post;
  final VoidCallback onReported;

  @override
  ConsumerState<_CirclePostReportSheet> createState() =>
      _CirclePostReportSheetState();
}

class _CirclePostReportSheetState
    extends ConsumerState<_CirclePostReportSheet> {
  final _detailsController = TextEditingController();
  ReportReason _reason = ReportReason.spam;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await ref
          .read(circlesRepositoryProvider)
          .reportPost(
            postId: widget.post.id,
            reason: _reason,
            details: _detailsController.text,
          );
      widget.onReported();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorText = tr('Could not submit report. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleFormBody(
      title: tr('Report post'),
      errorText: _errorText,
      actions: [
        WeCordButton(
          label: _isSubmitting ? tr('Submitting...') : tr('Submit report'),
          variant: WeCordButtonVariant.danger,
          expand: true,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
      children: [
        SettingsGroup(
          color: c.well,
          separatorIndent: 14,
          children: [
            for (final reason in ReportReason.values)
              SettingsRow(
                title: reason.label,
                showChevron: false,
                trailing: Icon(
                  reason == _reason
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: reason == _reason ? c.accent : c.faint,
                ),
                onTap: _isSubmitting
                    ? null
                    : () => setState(() => _reason = reason),
              ),
          ],
        ),
        const SizedBox(height: 14),
        WeCordTextField(
          controller: _detailsController,
          enabled: !_isSubmitting,
          maxLength: 1000,
          maxLines: 3,
          label: tr('Details'),
          inputFormatters: [LengthLimitingTextInputFormatter(1000)],
        ),
      ],
    );
  }
}

String _formatPostTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}
