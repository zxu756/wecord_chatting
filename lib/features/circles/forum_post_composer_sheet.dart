import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/mention_picker.dart';
import 'package:wecord/features/circles/circle_forum_view.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/models/group.dart';

/// Opens the new post form of a forum. Returns the created post, or null
/// when cancelled.
Future<ForumPost?> showForumPostComposer(
  BuildContext context, {
  required CircleChannel channel,
}) {
  return showModalBottomSheet<ForumPost>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ForumPostComposerSheet(channel: channel),
  );
}

/// The new post form: title, body (with @mentions of members who can see
/// the forum), tags and an optional image.
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
      final image = _image == null
          ? null
          : await repository.uploadForumImage(
              forumConversationId: widget.channel.conversationId,
              image: _image!,
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
        final autoMod = error is PostgrestException
            ? AutoModBlockedException.fromPostgrest(error)
            : null;
        setState(() {
          _saving = false;
          _errorText =
              autoMod?.toString() ??
              tr('Could not create the post. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _image;
    final query = _mentionQuery;
    // The forum's member list leaves out members who cannot see it.
    final candidates = query == null || _saving
        ? const <GroupMember>[]
        : mentionCandidates(
            ref
                    .watch(groupDetailProvider(widget.channel.conversationId))
                    .valueOrNull
                    ?.members ??
                const [],
            query,
          );
    return SafeArea(
      child: Padding(
        // Lifts the sheet above the keyboard, so the form scrolls within
        // the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('New post in {channel}', {'channel': widget.channel.name}),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('forum-post-title-field'),
                controller: _titleController,
                autofocus: true,
                enabled: !_saving,
                maxLength: ForumPost.maxTitleLength,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Title'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('forum-post-body-field'),
                controller: _bodyController,
                enabled: !_saving,
                minLines: 3,
                maxLines: 8,
                maxLength: ForumPost.maxBodyLength,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Message'),
                  alignLabelWithHint: true,
                ),
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
                const SizedBox(height: 4),
                Text(tr('Tags'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
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
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (image == null)
                    TextButton.icon(
                      key: const ValueKey('forum-post-add-image'),
                      onPressed: _saving || _picking ? null : _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(tr('Add image')),
                    )
                  else
                    Expanded(
                      child: InputChip(
                        key: const ValueKey('forum-post-image'),
                        avatar: const Icon(Icons.image_outlined),
                        label: Text(
                          image.fileName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: _saving
                            ? null
                            : () => setState(() => _image = null),
                        deleteButtonTooltipMessage: tr('Remove image'),
                      ),
                    ),
                ],
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(tr('Cancel')),
                  ),
                  FilledButton(
                    key: const ValueKey('forum-post-submit'),
                    onPressed: _saving ? null : _post,
                    child: Text(tr('Post')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
