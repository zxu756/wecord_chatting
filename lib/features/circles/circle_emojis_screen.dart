import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/shared/models/circle_emoji.dart';

void openCircleEmojisScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleEmojisScreen(circleId: circleId),
    ),
  );
}

/// A circle's custom emoji and stickers, in two tabs. Everyone in the
/// circle sees them; members with manage_emojis upload, rename and delete.
class CircleEmojisScreen extends ConsumerStatefulWidget {
  const CircleEmojisScreen({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleEmojisScreen> createState() => _CircleEmojisScreenState();
}

class _CircleEmojisScreenState extends ConsumerState<CircleEmojisScreen> {
  var _busy = false;

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Reloads this page and every picker after a change.
  void _refresh() {
    ref.invalidate(circleEmojisProvider(widget.circleId));
    ref.invalidate(usableEmojisProvider);
  }

  Future<void> _upload(CircleEmojiKind kind) async {
    if (_busy) {
      return;
    }
    final ChatImageUpload? image;
    try {
      image = await ref.read(imagePickerServiceProvider).pickImage();
    } catch (error) {
      _showSnackBar('Could not open the image. $error');
      return;
    }
    if (image == null || !mounted) {
      return;
    }
    if (circleEmojiImageMimeType(image.bytes) == null) {
      _showSnackBar('Choose a PNG, GIF or WebP image.');
      return;
    }
    if (image.bytes.length > maxCircleEmojiBytes) {
      _showSnackBar('Images can be at most 256 KB.');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _EmojiNameDialog(
        title: kind == CircleEmojiKind.sticker ? 'Name sticker' : 'Name emoji',
        initialName: suggestedCircleEmojiName(image!.fileName),
        submitLabel: 'Upload',
      ),
    );
    if (name == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(circleEmojiRepositoryProvider)
          .addCircleEmoji(
            circleId: widget.circleId,
            name: name,
            kind: kind,
            bytes: image.bytes,
          );
      _refresh();
      _showSnackBar(
        kind == CircleEmojiKind.sticker
            ? 'Sticker $name added.'
            : 'Emoji :$name: added.',
      );
    } on CircleEmojiException catch (error) {
      _showSnackBar(error.message);
    } catch (_) {
      _showSnackBar('Could not upload. Try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _rename(CircleEmoji emoji) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _EmojiNameDialog(
        title: emoji.isSticker ? 'Rename sticker' : 'Rename emoji',
        initialName: emoji.name,
        submitLabel: 'Save',
      ),
    );
    if (name == null || name == emoji.name || !mounted) {
      return;
    }
    try {
      await ref
          .read(circleEmojiRepositoryProvider)
          .renameCircleEmoji(emojiId: emoji.id, name: name);
      _refresh();
    } on CircleEmojiException catch (error) {
      _showSnackBar(error.message);
    } catch (_) {
      _showSnackBar('Could not rename. Try again.');
    }
  }

  Future<void> _delete(CircleEmoji emoji) async {
    final noun = emoji.isSticker ? 'sticker' : 'emoji';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Delete $noun'),
        content: Text(
          emoji.isSticker
              ? 'Delete the sticker ${emoji.name}? Messages that sent it '
                    'will no longer show it.'
              : 'Delete :${emoji.name}:? Messages show its name instead, '
                    'and reactions with it are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('circle-emoji-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(circleEmojiRepositoryProvider).deleteCircleEmoji(emoji.id);
      _refresh();
    } catch (_) {
      _showSnackBar('Could not delete. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final emojis = ref.watch(circleEmojisProvider(widget.circleId));
    final canManage =
        ref
            .watch(circleDetailProvider(widget.circleId))
            .valueOrNull
            ?.canManageEmojis ??
        false;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emoji & stickers'),
          bottom: const TabBar(
            tabs: [
              Tab(key: ValueKey('circle-emojis-tab-emoji'), text: 'Emoji'),
              Tab(
                key: ValueKey('circle-emojis-tab-stickers'),
                text: 'Stickers',
              ),
            ],
          ),
        ),
        body: emojis.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load emoji.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          data: (all) => TabBarView(
            children: [
              for (final kind in CircleEmojiKind.values)
                _EmojiKindTab(
                  kind: kind,
                  emojis: [
                    for (final emoji in all)
                      if (emoji.kind == kind) emoji,
                  ],
                  canManage: canManage,
                  busy: _busy,
                  onUpload: () => unawaited(_upload(kind)),
                  onRename: (emoji) => unawaited(_rename(emoji)),
                  onDelete: (emoji) => unawaited(_delete(emoji)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiKindTab extends StatelessWidget {
  const _EmojiKindTab({
    required this.kind,
    required this.emojis,
    required this.canManage,
    required this.busy,
    required this.onUpload,
    required this.onRename,
    required this.onDelete,
  });

  final CircleEmojiKind kind;
  final List<CircleEmoji> emojis;
  final bool canManage;
  final bool busy;
  final VoidCallback onUpload;
  final ValueChanged<CircleEmoji> onRename;
  final ValueChanged<CircleEmoji> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSticker = kind == CircleEmojiKind.sticker;
    final full = emojis.length >= kind.limit;
    final noun = isSticker ? 'stickers' : 'emoji';
    return ListView(
      key: ValueKey('circle-emojis-list-${kind.name}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            isSticker
                ? 'Stickers are sent on their own from the composer\'s '
                      'attach menu. PNG, GIF or WebP, up to 256 KB.'
                : 'Use emoji in messages by typing :name:, and as '
                      'reactions. PNG, GIF or WebP, up to 256 KB.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${emojis.length} of ${kind.limit} $noun',
                  key: ValueKey('circle-emojis-count-${kind.name}'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (canManage)
                FilledButton.icon(
                  key: ValueKey('circle-emojis-upload-${kind.name}'),
                  onPressed: busy || full ? null : onUpload,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: Text(isSticker ? 'Upload sticker' : 'Upload emoji'),
                ),
            ],
          ),
        ),
        if (emojis.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                isSticker ? 'No stickers yet' : 'No emoji yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final emoji in emojis)
          ListTile(
            key: ValueKey('circle-emoji-${emoji.id}'),
            leading: SizedBox.square(
              dimension: isSticker ? 56 : 40,
              child: Center(
                child: CustomEmojiImage(
                  storagePath: emoji.storagePath,
                  size: isSticker ? 56 : 32,
                  semanticLabel: emoji.name,
                  fallback: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            title: Text(
              isSticker ? emoji.name : ':${emoji.name}:',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: emoji.creatorName == null
                ? null
                : Text(
                    'Added by ${emoji.creatorName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: canManage
                ? PopupMenuButton<_EmojiAction>(
                    key: ValueKey('circle-emoji-menu-${emoji.id}'),
                    tooltip: 'More',
                    onSelected: (action) => switch (action) {
                      _EmojiAction.rename => onRename(emoji),
                      _EmojiAction.delete => onDelete(emoji),
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _EmojiAction.rename,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.drive_file_rename_outline),
                          title: Text('Rename'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _EmojiAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'Delete',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}

enum _EmojiAction { rename, delete }

/// Asks for an emoji or sticker name: 2 to 32 lowercase letters, digits or
/// underscores. Returns it, or null when cancelled.
class _EmojiNameDialog extends StatefulWidget {
  const _EmojiNameDialog({
    required this.title,
    required this.initialName,
    required this.submitLabel,
  });

  final String title;
  final String initialName;
  final String submitLabel;

  @override
  State<_EmojiNameDialog> createState() => _EmojiNameDialogState();
}

class _EmojiNameDialogState extends State<_EmojiNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim().toLowerCase();
    if (!circleEmojiNamePattern.hasMatch(name)) {
      setState(() {
        _errorText = 'Use 2 to 32 lowercase letters, digits or underscores.';
      });
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('circle-emoji-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 32,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Name',
          prefixText: ':',
          suffixText: ':',
          errorText: _errorText,
          errorMaxLines: 2,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('circle-emoji-name-submit'),
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
