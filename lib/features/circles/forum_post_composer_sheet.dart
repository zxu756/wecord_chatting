import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/mention_picker.dart';
import 'package:wecord/features/circles/circle_event_editor_sheet.dart';
import 'package:wecord/features/circles/circle_forum_view.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart'
    show ImageAttachment, cleanImageAlt, maxImageAltLength;
import 'package:wecord/shared/ui/ui.dart';

/// Opens the new post form of a forum. Returns the created post, or null
/// when cancelled.
Future<ForumPost?> showForumPostComposer(
  BuildContext context, {
  required CircleChannel channel,
}) {
  return showCircleFormSheet<ForumPost>(
    context,
    builder: (context) => ForumPostComposerSheet(channel: channel),
  );
}

/// The new post form: title, body (with @mentions of members who can see
/// the forum), tags and an optional image. In a media channel the picture is
/// required and can carry a description for people who cannot see it (L8); in
/// a Q&A channel it is a question.
class ForumPostComposerSheet extends ConsumerStatefulWidget {
  const ForumPostComposerSheet({required this.channel, super.key});

  final CircleChannel channel;

  @override
  ConsumerState<ForumPostComposerSheet> createState() =>
      _ForumPostComposerSheetState();
}

class _ForumPostComposerSheetState
    extends ConsumerState<ForumPostComposerSheet> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _altController = TextEditingController();
  final _tagIds = <String>{};
  final _mentionDraft = MentionDraft();
  String? _mentionQuery;
  ChatImageUpload? _image;
  var _saving = false;
  var _picking = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(_updateMentionQuery);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _altController.dispose();
    super.dispose();
  }

  void _updateMentionQuery() {
    final query = mentionQueryAt(_bodyController.value);
    if (query != _mentionQuery) {
      setState(() => _mentionQuery = query);
    }
  }

  void _insertMention(GroupMember member) {
    _mentionDraft.insert(_bodyController, member);
  }

  Future<void> _pickImage() async {
    setState(() => _picking = true);
    try {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (mounted && image != null) {
        setState(() => _image = image);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = tr('Could not open the image. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _post() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = tr('Give your post a title.'));
      return;
    }
    if (widget.channel.isMedia && _image == null) {
      setState(() => _errorText = tr('Add a picture to post here.'));
      return;
    }
    if (body.isEmpty && _image == null) {
      setState(() => _errorText = tr('Write something or add an image.'));
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final repository = ref.read(circlesRepositoryProvider);
    try {
      final uploaded = _image == null
          ? null
          : await repository.uploadForumImage(
              forumConversationId: widget.channel.conversationId,
              image: _image!,
            );
      // The description rides on the picture, as in chats and Moments.
      final alt = cleanImageAlt(_altController.text);
      final image = uploaded == null || alt == null
          ? uploaded
          : ImageAttachment(
              bucket: uploaded.bucket,
              path: uploaded.path,
              mimeType: uploaded.mimeType,
              size: uploaded.size,
              width: uploaded.width,
              height: uploaded.height,
              blurhash: uploaded.blurhash,
              alt: alt,
            );
      final post = await repository.createForumPost(
        channelId: widget.channel.id,
        title: title,
        body: body,
        tagIds: [
          for (final tag in widget.channel.tags)
            if (_tagIds.contains(tag.id)) tag.id,
        ],
        image: image,
        mentions: _mentionDraft.mentionsFor(body),
      );
      if (mounted) {
        Navigator.of(context).pop(post);
      }
    } catch (error) {
      if (mounted) {
        final refused = switch (error) {
          SendRefusedException() => error,
          PostgrestException() => SendRefusedException.fromPostgrest(error),
          _ => null,
        };
        setState(() {
          _saving = false;
          _errorText =
              refused?.toString() ??
              tr('Could not create the post. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final query = _mentionQuery;
    // The forum's member list leaves out members who cannot see it.
    final candidates = query == null || _saving
        ? const <GroupMember>[]
        : mentionCandidates(
            ref
                    .watch(groupDetailProvider(widget.channel.conversationId))
                    .value
                    ?.members ??
                const [],
            query,
          );
    final c = context.tokens.colors;
    return CircleFormBody(
      title: widget.channel.isQa
          ? tr('Ask in {channel}', {'channel': widget.channel.name})
          : tr('New post in {channel}', {'channel': widget.channel.name}),
      errorText: _errorText,
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.secondary,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        WeCordButton(
          key: const ValueKey('forum-post-submit'),
          label: tr('Post'),
          variant: WeCordButtonVariant.accent,
          loading: _saving,
          onPressed: _saving ? null : _post,
        ),
      ],
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('forum-post-title-field'),
          controller: _titleController,
          autofocus: true,
          enabled: !_saving,
          maxLength: ForumPost.maxTitleLength,
          textInputAction: TextInputAction.next,
          label: widget.channel.isQa ? tr('Question') : tr('Title'),
        ),
        const SizedBox(height: 4),
        WeCordTextField(
          fieldKey: const ValueKey('forum-post-body-field'),
          controller: _bodyController,
          enabled: !_saving,
          minLines: 3,
          maxLines: 8,
          maxLength: ForumPost.maxBodyLength,
          keyboardType: TextInputType.multiline,
          label: widget.channel.isQa ? tr('Details') : tr('Message'),
        ),
        if (candidates.isNotEmpty) ...[
          MentionCandidateList(
            key: const ValueKey('forum-post-mention-candidates'),
            candidates: candidates,
            onSelect: _insertMention,
            maxHeight: 180,
          ),
          const SizedBox(height: 8),
        ],
        if (widget.channel.tags.isNotEmpty) ...[
          CircleFormLabel(tr('Tags')),
          ForumTagSelector(
            tags: widget.channel.tags,
            selected: _tagIds,
            enabled: !_saving,
            onChanged: (selected) => setState(() {
              _tagIds
                ..clear()
                ..addAll(selected);
            }),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        if (image == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: WeCordButton(
              key: const ValueKey('forum-post-add-image'),
              variant: WeCordButtonVariant.secondary,
              onPressed: _saving || _picking ? null : _pickImage,
              icon: Icons.image_outlined,
              label: widget.channel.isMedia
                  ? tr('Add picture')
                  : tr('Add image'),
            ),
          )
        else
          Container(
            key: const ValueKey('forum-post-image'),
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 20, color: c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    image.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                WeCordIconButton(
                  tooltip: tr('Remove image'),
                  icon: Icons.close_rounded,
                  variant: WeCordButtonVariant.ghost,
                  size: 32,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _image = null),
                ),
              ],
            ),
          ),
        if (image != null) ...[
          const SizedBox(height: 12),
          WeCordTextField(
            fieldKey: const ValueKey('forum-post-image-alt-field'),
            controller: _altController,
            enabled: !_saving,
            minLines: 2,
            maxLines: 4,
            maxLength: maxImageAltLength,
            keyboardType: TextInputType.multiline,
            label: trIn('picture-description', 'Description'),
            hint: tr('A dog asleep on a red sofa'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('Helps people who cannot see the picture.'),
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
        ],
      ],
    );
  }
}
