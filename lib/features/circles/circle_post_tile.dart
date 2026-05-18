import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/report_reason.dart';

enum _PostAction { delete, report }

class CirclePostTile extends ConsumerWidget {
  const CirclePostTile({
    required this.post,
    required this.onChanged,
    super.key,
  });

  final CirclePost post;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Text(_initials(post.author.displayLabel))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author.displayLabel,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      _formatPostTime(post.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PostAction>(
                tooltip: 'Post actions',
                onSelected: (action) async {
                  switch (action) {
                    case _PostAction.delete:
                      await _deletePost(context, ref);
                    case _PostAction.report:
                      await showCirclePostReportSheet(
                        context,
                        post: post,
                        onReported: onChanged,
                      );
                  }
                },
                itemBuilder: (context) => [
                  if (post.isOwnPost || post.canManagePost)
                    const PopupMenuItem(
                      value: _PostAction.delete,
                      child: Text('Delete'),
                    )
                  else
                    const PopupMenuItem(
                      value: _PostAction.report,
                      child: Text('Report'),
                    ),
                ],
              ),
            ],
          ),
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(post.body),
          ],
          if (post.imageAttachment != null) ...[
            const SizedBox(height: 10),
            _PostImagePreview(attachment: post.imageAttachment!),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Tooltip(
                message: post.likedByCurrentUser ? 'Unlike post' : 'Like post',
                child: TextButton.icon(
                  onPressed: () => _toggleLike(ref),
                  icon: Icon(
                    post.likedByCurrentUser
                        ? Icons.favorite
                        : Icons.favorite_border,
                  ),
                  label: Text('${post.likeCount}'),
                  style: TextButton.styleFrom(
                    foregroundColor: post.likedByCurrentUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Tooltip(
                message: 'Comment',
                child: TextButton.icon(
                  onPressed: () => showCirclePostCommentSheet(
                    context,
                    post: post,
                    onCommented: onChanged,
                  ),
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text('${post.commentCount}'),
                ),
              ),
            ],
          ),
          if (post.comments.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final comment in post.comments.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${comment.author.displayLabel}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: comment.body),
                    ],
                  ),
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
          const SnackBar(content: Text('Could not delete post. Try again.')),
        );
      }
    }
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
          borderRadius: BorderRadius.circular(8),
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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
          _errorText = 'Could not comment. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comment', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_isSubmitting,
              maxLines: 4,
              inputFormatters: [LengthLimitingTextInputFormatter(1000)],
              decoration: const InputDecoration(
                labelText: 'Comment',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: Text(_isSubmitting ? 'Commenting...' : 'Comment'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCirclePostReportSheet(
  BuildContext context, {
  required CirclePost post,
  required VoidCallback onReported,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
          _errorText = 'Could not submit report. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Report post', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (!_isSubmitting && value != null) {
                  setState(() => _reason = value);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      contentPadding: EdgeInsets.zero,
                      value: reason,
                      title: Text(reason.label),
                      enabled: !_isSubmitting,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _detailsController,
              enabled: !_isSubmitting,
              maxLength: 1000,
              maxLines: 3,
              inputFormatters: [LengthLimitingTextInputFormatter(1000)],
              decoration: const InputDecoration(
                labelText: 'Details',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: Text(_isSubmitting ? 'Submitting...' : 'Submit report'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPostTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

String _initials(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}
