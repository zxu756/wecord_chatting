import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/notes/note_block_views.dart';
import 'package:wecord/features/notes/note_comments_controller.dart';
import 'package:wecord/features/notes/note_editor.dart'
    show NoteMentionCandidate;
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A date and time the way the rest of the notes show them.
String noteTimeText(BuildContext context, DateTime time) {
  final when = MaterialLocalizations.of(context);
  final local = time.toLocal();
  return '${when.formatShortDate(local)} '
      '${when.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// Opens the comments of a note as a sheet: open threads and resolved ones,
/// replies, resolving, editing and a box for a comment on the note itself.
/// [focusBlockId] scrolls to the comments of one block.
Future<void> showNoteComments(
  BuildContext context, {
  required NoteCommentsController controller,
  required List<GroupMember> members,
  required bool canComment,
  String? focusBlockId,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Comments'),
    detents: const [0.6, 0.92],
    initialDetent: 0.92,
    builder: (context, scrollController) => NoteCommentsPanel(
      controller: controller,
      members: members,
      canComment: canComment,
      focusBlockId: focusBlockId,
      scrollController: scrollController,
    ),
  );
}

/// Asks for a comment on [quote] (the words selected, or the block's) and
/// hands the text and the people mentioned to [onSubmit].
Future<void> showNewNoteComment(
  BuildContext context, {
  required List<GroupMember> members,
  required Future<void> Function(String body, List<String> mentions) onSubmit,
  String? quote,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('New comment'),
    builder: (context, _) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quote != null && quote.trim().isNotEmpty) ...[
            NoteCommentQuote(text: quote),
            const SizedBox(height: 10),
          ],
          NoteCommentComposer(
            members: members,
            autofocus: true,
            hint: tr('Write a comment'),
            submitLabel: tr('Comment'),
            onSubmit: (body, mentions) async {
              await onSubmit(body, mentions);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// The words a comment was made on, quoted.
class NoteCommentQuote extends StatelessWidget {
  const NoteCommentQuote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('note-comment-quote'),
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.warning, width: 3)),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
      ),
    );
  }
}

/// A box to write a comment in, with @mentions of the note's people.
/// [onSubmit] gets the text and the ids of the people named in it.
class NoteCommentComposer extends StatefulWidget {
  const NoteCommentComposer({
    required this.members,
    required this.onSubmit,
    required this.hint,
    required this.submitLabel,
    this.initialText = '',
    this.autofocus = false,
    this.onCancel,
    super.key,
  });

  final List<GroupMember> members;
  final Future<void> Function(String body, List<String> mentions) onSubmit;
  final String hint;
  final String submitLabel;
  final String initialText;
  final bool autofocus;
  final VoidCallback? onCancel;

  @override
  State<NoteCommentComposer> createState() => _NoteCommentComposerState();
}

class _NoteCommentComposerState extends State<NoteCommentComposer> {
  late final TextEditingController _text;
  final _focus = FocusNode(debugLabel: 'note comment');
  // The people picked from the @ list, by the name that was put in the text.
  final _picked = <String, String>{};
  ({int start, int end, String query})? _mention;
  var _sending = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText)
      ..addListener(_onText);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    final selection = _text.selection;
    final text = _text.text;
    final caret = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final match = RegExp(
      r'(?:^|\s)@([^\s@]{0,24})$',
    ).firstMatch(text.substring(0, caret));
    final next = match == null
        ? null
        : (
            start: caret - match.group(1)!.length - 1,
            end: caret,
            query: match.group(1)!.toLowerCase(),
          );
    if (next != _mention) {
      setState(() => _mention = next);
    } else {
      setState(() {});
    }
  }

  List<NoteMentionCandidate> _candidates() {
    final mention = _mention;
    if (mention == null) {
      return const [];
    }
    final result = <NoteMentionCandidate>[];
    for (final member in widget.members) {
      final nickname = member.nickname?.trim();
      final label = nickname == null || nickname.isEmpty
          ? member.profile.displayName
          : nickname;
      if (mention.query.isEmpty ||
          label.toLowerCase().contains(mention.query) ||
          member.profile.username.toLowerCase().contains(mention.query)) {
        result.add((userId: member.profile.id, label: '@$label'));
      }
      if (result.length >= 5) {
        break;
      }
    }
    return result;
  }

  void _pick(NoteMentionCandidate candidate) {
    final mention = _mention;
    if (mention == null) {
      return;
    }
    final text = _text.text;
    final replaced = text.replaceRange(
      mention.start,
      mention.end,
      '${candidate.label} ',
    );
    _picked[candidate.label] = candidate.userId;
    _text.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(
        offset: mention.start + candidate.label.length + 1,
      ),
    );
    _focus.requestFocus();
  }

  /// The people whose @name is still in the text.
  List<String> _mentions() {
    final text = _text.text;
    return {
      for (final entry in _picked.entries)
        if (text.contains(entry.key)) entry.value,
    }.toList();
  }

  bool get _canSend => _text.text.trim().isNotEmpty && !_sending;

  Future<void> _send() async {
    if (!_canSend) {
      return;
    }
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await widget.onSubmit(_text.text.trim(), _mentions());
      if (mounted) {
        _text.clear();
        _picked.clear();
      }
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final candidates = _candidates();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (candidates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: NoteMentionTray(candidates: candidates, onPick: _pick),
          ),
        WeCordTextField(
          controller: _text,
          focusNode: _focus,
          hint: widget.hint,
          autofocus: widget.autofocus,
          maxLines: 6,
          minLines: 2,
          maxLength: 2000,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          fieldKey: const ValueKey('note-comment-field'),
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                tr('Could not send the comment. Try again.'),
                style: TextStyle(fontSize: 13, color: c.dangerText),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onCancel != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: WeCordButton(
                  label: tr('Cancel'),
                  variant: WeCordButtonVariant.ghost,
                  size: WeCordButtonSize.small,
                  onPressed: widget.onCancel,
                ),
              ),
            WeCordButton(
              key: const ValueKey('note-comment-send'),
              label: widget.submitLabel,
              size: WeCordButtonSize.small,
              onPressed: _canSend ? () => unawaited(_send()) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// The comments of a note.
class NoteCommentsPanel extends StatefulWidget {
  const NoteCommentsPanel({
    required this.controller,
    required this.members,
    required this.canComment,
    this.focusBlockId,
    this.scrollController,
    super.key,
  });

  final NoteCommentsController controller;
  final List<GroupMember> members;
  final bool canComment;
  final String? focusBlockId;
  final ScrollController? scrollController;

  @override
  State<NoteCommentsPanel> createState() => _NoteCommentsPanelState();
}

class _NoteCommentsPanelState extends State<NoteCommentsPanel> {
  var _showResolved = false;
  String? _replyingTo;
  String? _editing;

  NoteCommentsController get _controller => widget.controller;

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) {
        _toast(tr('That did not work. Try again.'));
      }
    }
  }

  Future<void> _delete(NoteComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          comment.isReply
              ? tr('Delete this reply?')
              : tr('Delete this comment?'),
        ),
        content: comment.isReply
            ? null
            : Text(tr('Its replies are deleted with it.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _guard(() => _controller.delete(comment));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final open = _controller.openThreads;
        final resolved = _controller.resolvedThreads;
        final shown = _showResolved ? resolved : open;
        if (widget.focusBlockId != null && !_showResolved) {
          shown.sort((a, b) {
            final aFocus = a.root.blockId == widget.focusBlockId ? 0 : 1;
            final bFocus = b.root.blockId == widget.focusBlockId ? 0 : 1;
            return aFocus.compareTo(bFocus);
          });
        }
        Widget body;
        if (_controller.loading) {
          body = const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        } else if (_controller.error != null && _controller.comments.isEmpty) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('Could not load the comments.'),
                    style: TextStyle(color: c.dangerText),
                  ),
                  const SizedBox(height: 12),
                  WeCordButton(
                    label: tr('Try again'),
                    size: WeCordButtonSize.small,
                    onPressed: () => unawaited(_controller.refresh()),
                  ),
                ],
              ),
            ),
          );
        } else if (shown.isEmpty) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _showResolved
                    ? tr('No resolved comments.')
                    : tr(
                        'No comments yet. Select some words and tap the '
                        'comment button to start a conversation.',
                      ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
              ),
            ),
          );
        } else {
          body = ListView.separated(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ThreadCard(
              key: ValueKey('note-thread-${shown[index].root.id}'),
              thread: shown[index],
              members: widget.members,
              canComment: widget.canComment,
              replying: _replyingTo == shown[index].root.id,
              editingId: _editing,
              onReply: () => setState(() => _replyingTo = shown[index].root.id),
              onCancelReply: () => setState(() => _replyingTo = null),
              onSendReply: (body, mentions) async {
                await _controller.reply(
                  shown[index].root,
                  body,
                  mentions: mentions,
                );
                if (mounted) {
                  setState(() => _replyingTo = null);
                }
              },
              onResolve: (resolved) => unawaited(
                _guard(
                  () => _controller.setResolved(shown[index].root, resolved),
                ),
              ),
              onEdit: (comment) => setState(() => _editing = comment.id),
              onCancelEdit: () => setState(() => _editing = null),
              onSaveEdit: (comment, body) async {
                await _controller.edit(comment, body);
                if (mounted) {
                  setState(() => _editing = null);
                }
              },
              onDelete: (comment) => unawaited(_delete(comment)),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: WeCordSegmented<bool>(
                expand: true,
                semanticLabel: tr('Which comments'),
                selected: _showResolved,
                onChanged: (value) => setState(() => _showResolved = value),
                segments: [
                  WeCordSegment(
                    value: false,
                    label: tr('Open ({count})', {'count': '${open.length}'}),
                  ),
                  WeCordSegment(
                    value: true,
                    label: tr('Resolved ({count})', {
                      'count': '${resolved.length}',
                    }),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
            if (widget.canComment && !_showResolved)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  12 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: NoteCommentComposer(
                  members: widget.members,
                  hint: tr('Comment on the whole note'),
                  submitLabel: tr('Comment'),
                  onSubmit: (body, mentions) =>
                      _controller.add(body, mentions: mentions),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    required this.thread,
    required this.members,
    required this.canComment,
    required this.replying,
    required this.editingId,
    required this.onReply,
    required this.onCancelReply,
    required this.onSendReply,
    required this.onResolve,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
    required this.onDelete,
    super.key,
  });

  final NoteCommentThread thread;
  final List<GroupMember> members;
  final bool canComment;
  final bool replying;
  final String? editingId;
  final VoidCallback onReply;
  final VoidCallback onCancelReply;
  final Future<void> Function(String body, List<String> mentions) onSendReply;
  final ValueChanged<bool> onResolve;
  final ValueChanged<NoteComment> onEdit;
  final VoidCallback onCancelEdit;
  final Future<void> Function(NoteComment comment, String body) onSaveEdit;
  final ValueChanged<NoteComment> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final root = thread.root;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: thread.isResolved ? c.panel : c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        border: Border.all(color: c.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (root.anchorText != null && root.anchorText!.isNotEmpty) ...[
            NoteCommentQuote(text: root.anchorText!),
            const SizedBox(height: 8),
          ],
          _CommentRow(
            comment: root,
            editing: editingId == root.id,
            members: members,
            onEdit: onEdit,
            onCancelEdit: onCancelEdit,
            onSaveEdit: onSaveEdit,
            onDelete: onDelete,
          ),
          for (final reply in thread.replies) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: _CommentRow(
                comment: reply,
                editing: editingId == reply.id,
                members: members,
                onEdit: onEdit,
                onCancelEdit: onCancelEdit,
                onSaveEdit: onSaveEdit,
                onDelete: onDelete,
              ),
            ),
          ],
          if (thread.isResolved)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                root.resolvedByName == null || root.resolvedByName!.isEmpty
                    ? tr('Resolved')
                    : tr('Resolved by {name}', {'name': root.resolvedByName!}),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: c.success,
                ),
              ),
            ),
          if (replying)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: NoteCommentComposer(
                members: members,
                autofocus: true,
                hint: tr('Write a reply'),
                submitLabel: tr('Reply'),
                onSubmit: onSendReply,
                onCancel: onCancelReply,
              ),
            ),
          if (!replying && (canComment || root.canResolve))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                children: [
                  if (canComment && !thread.isResolved)
                    WeCordButton(
                      label: tr('Reply'),
                      variant: WeCordButtonVariant.ghost,
                      size: WeCordButtonSize.small,
                      icon: Icons.reply_rounded,
                      onPressed: onReply,
                    ),
                  if (root.canResolve)
                    WeCordButton(
                      label: thread.isResolved ? tr('Reopen') : tr('Resolve'),
                      variant: WeCordButtonVariant.ghost,
                      size: WeCordButtonSize.small,
                      icon: thread.isResolved
                          ? Icons.undo_rounded
                          : Icons.check_rounded,
                      onPressed: () => onResolve(!thread.isResolved),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.editing,
    required this.members,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
    required this.onDelete,
  });

  final NoteComment comment;
  final bool editing;
  final List<GroupMember> members;
  final ValueChanged<NoteComment> onEdit;
  final VoidCallback onCancelEdit;
  final Future<void> Function(NoteComment comment, String body) onSaveEdit;
  final ValueChanged<NoteComment> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final avatar = comment.authorAvatarUrl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PersonAvatar(
          name: comment.authorName,
          size: 28,
          image: avatar == null || avatar.isEmpty ? null : NetworkImage(avatar),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comment.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          noteTimeText(context, comment.createdAt) +
                              (comment.editedAt == null
                                  ? ''
                                  : ' · ${tr('edited')}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.subtle),
                        ),
                      ],
                    ),
                  ),
                  if (comment.canEdit || comment.canDelete)
                    PopupMenuButton<String>(
                      tooltip: tr('Comment options'),
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: c.muted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit(comment);
                        } else {
                          onDelete(comment);
                        }
                      },
                      itemBuilder: (context) => [
                        if (comment.canEdit)
                          PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                        if (comment.canDelete)
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(tr('Delete')),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 2),
              if (editing)
                NoteCommentComposer(
                  members: members,
                  initialText: comment.body,
                  autofocus: true,
                  hint: tr('Write a comment'),
                  submitLabel: tr('Save'),
                  onSubmit: (body, _) => onSaveEdit(comment, body),
                  onCancel: onCancelEdit,
                )
              else
                Text(
                  comment.body,
                  style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
