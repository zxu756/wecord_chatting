import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/message.dart';

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
  ChatImageUpload? _selectedImage;
  bool _isPickingImage = false;
  bool _isPosting = false;
  String? _errorText;

  @override
  void dispose() {
    _bodyController.dispose();
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
        setState(() => _errorText = 'Could not choose image. Try again.');
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
      await repository.createPost(
        circleId: widget.circleId,
        body: body,
        image: uploadedImage,
      );
      if (!mounted) {
        return;
      }
      _bodyController.clear();
      setState(() {
        _selectedImage = null;
        _isPosting = false;
      });
      widget.onPosted();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPosting = false;
        _errorText = 'Could not post. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedImage = _selectedImage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _bodyController,
            enabled: !_isPosting,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Share with this Circle',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Add image',
                icon: _isPickingImage
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                onPressed: _isPickingImage || _isPosting ? null : _pickImage,
              ),
            ),
          ),
          if (selectedImage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.image_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selectedImage.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove image',
                  icon: const Icon(Icons.close),
                  onPressed: _isPosting
                      ? null
                      : () => setState(() => _selectedImage = null),
                ),
              ],
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: 'Post',
              child: FilledButton.icon(
                icon: _isPosting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_isPosting ? 'Posting...' : 'Post'),
                onPressed: _isPosting ? null : _post,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
