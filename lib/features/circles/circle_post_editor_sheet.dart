import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_event_editor_sheet.dart';
import 'package:wecord/features/circles/circle_posts_repository.dart';
import 'package:wecord/features/hashtags/hashtag_text.dart';
import 'package:wecord/features/hashtags/hashtag_widgets.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Edits one of the caller's own posts: title, text and picked topics (the
/// picture stays). [onSaved] runs once it is saved.
Future<void> showCirclePostEditSheet(
  BuildContext context, {
  required CirclePost post,
  required VoidCallback onSaved,
}) {
  return showCircleFormSheet<void>(
    context,
    builder: (_) => CirclePostEditSheet(post: post, onSaved: onSaved),
  );
}

class CirclePostEditSheet extends ConsumerStatefulWidget {
  const CirclePostEditSheet({
    required this.post,
    required this.onSaved,
    super.key,
  });

  final CirclePost post;
  final VoidCallback onSaved;

  @override
  ConsumerState<CirclePostEditSheet> createState() =>
      _CirclePostEditSheetState();
}

class _CirclePostEditSheetState extends ConsumerState<CirclePostEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late List<String> _tags;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final post = widget.post;
    _title = TextEditingController(text: post.title ?? '');
    _body = TextEditingController(text: post.body);
    // The topics written in the title and the text come back from them, so
    // only the others are picked ones.
    final written = {
      ...extractHashtags(post.title),
      ...extractHashtags(post.body),
    };
    _tags = [
      for (final tag in post.tags)
        if (!written.contains(tag)) tag,
    ];
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (_isSaving) {
      return;
    }
    if (body.isEmpty && widget.post.attachment == null) {
      setState(() => _errorText = tr('Write something first.'));
      return;
    }
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(circlePostsRepositoryProvider)
          .update(
            postId: widget.post.id,
            body: body,
            title: _title.text,
            tags: _tags,
          );
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleFormBody(
      title: tr('Edit post'),
      errorText: _errorText,
      actions: [
        WeCordButton(
          label: _isSaving ? tr('Saving...') : tr('Save'),
          expand: true,
          onPressed: _isSaving ? null : _save,
        ),
      ],
      children: [
        WeCordTextField(
          controller: _title,
          enabled: !_isSaving,
          label: tr('Title'),
          hint: tr('Title (optional)'),
          maxLength: CirclePostsRepository.maxTitleLength,
          inputFormatters: [
            LengthLimitingTextInputFormatter(
              CirclePostsRepository.maxTitleLength,
            ),
            FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
          ],
        ),
        const SizedBox(height: 12),
        WeCordTextField(
          controller: _body,
          enabled: !_isSaving,
          label: tr('Text'),
          minLines: 3,
          maxLines: 8,
        ),
        const SizedBox(height: 12),
        HashtagEditor(
          tags: _tags,
          enabled: !_isSaving,
          onChanged: (tags) => setState(() => _tags = tags),
        ),
      ],
    );
  }
}
