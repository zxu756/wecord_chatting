import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circle_posts_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/hashtags/hashtag_widgets.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class CircleFeedComposer extends ConsumerStatefulWidget {
  const CircleFeedComposer({
    required this.circleId,
    required this.onPosted,
    super.key,
  });

  final String circleId;
  final VoidCallback onPosted;

  @override
  ConsumerState<CircleFeedComposer> createState() => _CircleFeedComposerState();
}

class _CircleFeedComposerState extends ConsumerState<CircleFeedComposer> {
  final _bodyController = TextEditingController();
  final _titleController = TextEditingController();
  List<String> _tags = const [];
  bool _showTopics = false;
  ChatImageUpload? _selectedImage;
  bool _isPickingImage = false;
  bool _isPosting = false;
  String? _errorText;

  @override
  void dispose() {
    _bodyController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isPickingImage || _isPosting) {
      return;
    }
    setState(() {
      _isPickingImage = true;
      _errorText = null;
    });

    try {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (!mounted) {
        return;
      }
      if (image != null) {
        setState(() => _selectedImage = image);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = tr('Could not choose image. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _post() async {
    final body = _bodyController.text.trim();
    if (_isPosting || (body.isEmpty && _selectedImage == null)) {
      return;
    }

    setState(() {
      _isPosting = true;
      _errorText = null;
    });

    try {
      final repository = ref.read(circlesRepositoryProvider);
      ImageAttachment? uploadedImage;
      final selectedImage = _selectedImage;
      if (selectedImage != null) {
        uploadedImage = await repository.uploadPostImage(
          circleId: widget.circleId,
          image: selectedImage,
        );
      }
      await ref
          .read(circlePostsRepositoryProvider)
          .create(
            circleId: widget.circleId,
            body: body,
            title: _titleController.text,
            tags: _tags,
            image: uploadedImage,
          );
      if (!mounted) {
        return;
      }
      _bodyController.clear();
      _titleController.clear();
      setState(() {
        _selectedImage = null;
        _tags = const [];
        _showTopics = false;
        _isPosting = false;
      });
      widget.onPosted();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPosting = false;
        _errorText = error is PostgrestException
            ? errorText(error)
            : tr('Could not post. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final selectedImage = _selectedImage;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            controller: _titleController,
            enabled: !_isPosting,
            onPaper: true,
            hint: tr('Title (optional)'),
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                CirclePostsRepository.maxTitleLength,
              ),
              FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
            ],
          ),
          const SizedBox(height: 8),
          WeCordTextField(
            controller: _bodyController,
            enabled: !_isPosting,
            minLines: 1,
            maxLines: 4,
            onPaper: true,
            hint: tr('Share with this Circle'),
            suffix: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WeCordIconButton(
                    tooltip: _showTopics ? tr('Hide topics') : tr('Add topics'),
                    icon: Icons.tag_rounded,
                    variant: _tags.isNotEmpty || _showTopics
                        ? WeCordButtonVariant.secondary
                        : WeCordButtonVariant.ghost,
                    size: 36,
                    onPressed: _isPosting
                        ? null
                        : () => setState(() => _showTopics = !_showTopics),
                  ),
                  if (_isPickingImage)
                    const SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    WeCordIconButton(
                      tooltip: tr('Add image'),
                      icon: Icons.image_outlined,
                      variant: WeCordButtonVariant.ghost,
                      size: 36,
                      onPressed: _isPosting ? null : _pickImage,
                    ),
                ],
              ),
            ),
          ),
          if (_showTopics || _tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            HashtagEditor(
              tags: _tags,
              enabled: !_isPosting,
              onChanged: (tags) => setState(() => _tags = tags),
            ),
          ],
          if (selectedImage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, size: 18, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedImage.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
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
                    onPressed: _isPosting
                        ? null
                        : () => setState(() => _selectedImage = null),
                  ),
                ],
              ),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.dangerText,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: tr('Post'),
              child: WeCordButton(
                variant: WeCordButtonVariant.accent,
                size: usesTouchInput(context)
                    ? WeCordButtonSize.medium
                    : WeCordButtonSize.small,
                icon: Icons.send_rounded,
                label: _isPosting ? tr('Posting...') : tr('Post'),
                onPressed: _isPosting ? null : _post,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
