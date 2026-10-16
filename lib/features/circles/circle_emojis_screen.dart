import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/ui/ui.dart';

void openCircleEmojisScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleEmojisScreen(circleId: circleId),
    ),
  );
}

/// A circle's custom emoji and stickers, in two segments. Everyone in the
/// circle sees them; members with manage_emojis upload, rename and delete.
class CircleEmojisScreen extends ConsumerStatefulWidget {
  const CircleEmojisScreen({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleEmojisScreen> createState() => _CircleEmojisScreenState();
}

class _CircleEmojisScreenState extends ConsumerState<CircleEmojisScreen> {
  var _busy = false;
  var _kind = CircleEmojiKind.emoji;

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
      _showSnackBar(tr('Could not open the image. {error}', {'error': error}));
      return;
    }
    if (image == null || !mounted) {
      return;
    }
    if (circleEmojiImageMimeType(image.bytes) == null) {
      _showSnackBar(tr('Choose a PNG, GIF or WebP image.'));
      return;
    }
    if (image.bytes.length > maxCircleEmojiBytes) {
      _showSnackBar(tr('Images can be at most 256 KB.'));
      return;
    }
    final name = await showCircleDialog<String>(
      context,
      builder: (context) => _EmojiNameDialog(
        title: kind == CircleEmojiKind.sticker
            ? tr('Name sticker')
            : tr('Name emoji'),
        initialName: suggestedCircleEmojiName(image!.fileName),
        submitLabel: tr('Upload'),
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
            ? tr('Sticker {name} added.', {'name': name})
            : tr('Emoji :{name}: added.', {'name': name}),
      );
    } on CircleEmojiException catch (error) {
      _showSnackBar(error.message);
    } catch (_) {
      _showSnackBar(tr('Could not upload. Try again.'));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _rename(CircleEmoji emoji) async {
    final name = await showCircleDialog<String>(
      context,
      builder: (context) => _EmojiNameDialog(
        title: emoji.isSticker ? tr('Rename sticker') : tr('Rename emoji'),
        initialName: emoji.name,
        submitLabel: tr('Save'),
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
      _showSnackBar(tr('Could not rename. Try again.'));
    }
  }

  Future<void> _delete(CircleEmoji emoji) async {
    final confirmed = await showCircleDialog<bool>(
      context,
      builder: (context) => CircleDialog(
        title: emoji.isSticker ? tr('Delete sticker') : tr('Delete emoji'),
        message: emoji.isSticker
            ? tr(
                'Delete the sticker {name}? Messages that sent it '
                'will no longer show it.',
                {'name': emoji.name},
              )
            : tr(
                'Delete :{name}:? Messages show its name instead, '
                'and reactions with it are removed.',
                {'name': emoji.name},
              ),
        actions: [
          CircleDialogAction(
            label: tr('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CircleDialogAction.danger(
            key: const ValueKey('circle-emoji-delete-confirm'),
            label: tr('Delete'),
            onPressed: () => Navigator.of(context).pop(true),
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
      _showSnackBar(tr('Could not delete. Try again.'));
    }
  }

  Future<void> _openMenu(CircleEmoji emoji, Offset? position) async {
    final action = await showCircleActionMenu<_EmojiAction>(
      context,
      title: emoji.isSticker ? emoji.name : ':${emoji.name}:',
      position: position,
      items: [
        CircleMenuItem(
          value: _EmojiAction.rename,
          icon: Icons.drive_file_rename_outline,
          label: tr('Rename'),
        ),
        CircleMenuItem(
          value: _EmojiAction.delete,
          icon: Icons.delete_outline,
          label: tr('Delete'),
          destructive: true,
        ),
      ],
    );
    switch (action) {
      case _EmojiAction.rename:
        await _rename(emoji);
      case _EmojiAction.delete:
        await _delete(emoji);
      case null:
        break;
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
    final kind = _kind;
    return CirclePageScaffold(
      title: tr('Emoji & stickers'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: WeCordSegmented<CircleEmojiKind>(
              expand: true,
              selected: kind,
              onChanged: (kind) => setState(() => _kind = kind),
              segments: [
                WeCordSegment(
                  key: const ValueKey('circle-emojis-tab-emoji'),
                  value: CircleEmojiKind.emoji,
                  label: tr('Emoji'),
                ),
                WeCordSegment(
                  key: const ValueKey('circle-emojis-tab-stickers'),
                  value: CircleEmojiKind.sticker,
                  label: tr('Stickers'),
                ),
              ],
            ),
          ),
          Expanded(
            child: emojis.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => CircleEmptyState(
                icon: Icons.emoji_emotions_outlined,
                title: tr('Could not load emoji.'),
              ),
              data: (all) => _EmojiKindTab(
                key: ValueKey('circle-emojis-tab-view-${kind.name}'),
                kind: kind,
                emojis: [
                  for (final emoji in all)
                    if (emoji.kind == kind) emoji,
                ],
                canManage: canManage,
                busy: _busy,
                onUpload: () => unawaited(_upload(kind)),
                onMenu: (emoji, position) =>
                    unawaited(_openMenu(emoji, position)),
              ),
            ),
          ),
        ],
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
    required this.onMenu,
    super.key,
  });

  final CircleEmojiKind kind;
  final List<CircleEmoji> emojis;
  final bool canManage;
  final bool busy;
  final VoidCallback onUpload;

  /// Opens an emoji's menu, at a global position on wide screens.
  final void Function(CircleEmoji emoji, Offset? position) onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final isSticker = kind == CircleEmojiKind.sticker;
    final full = emojis.length >= kind.limit;
    return ListView(
      key: ValueKey('circle-emojis-list-${kind.name}'),
      padding: circlePagePadding(context),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: Text(
            isSticker
                ? tr(
                    'Stickers are sent on their own from the composer\'s '
                    'attach menu. PNG, GIF or WebP, up to 256 KB.',
                  )
                : tr(
                    'Use emoji in messages by typing :name:, and as '
                    'reactions. PNG, GIF or WebP, up to 256 KB.',
                  ),
            style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 0, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isSticker
                      ? tr('{count} of {limit} stickers', {
                          'count': emojis.length,
                          'limit': kind.limit,
                        })
                      : tr('{count} of {limit} emoji', {
                          'count': emojis.length,
                          'limit': kind.limit,
                        }),
                  key: ValueKey('circle-emojis-count-${kind.name}'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              if (canManage)
                WeCordButton(
                  key: ValueKey('circle-emojis-upload-${kind.name}'),
                  label: isSticker ? tr('Upload sticker') : tr('Upload emoji'),
                  icon: Icons.upload_outlined,
                  variant: WeCordButtonVariant.onPaper,
                  loading: busy,
                  onPressed: busy || full ? null : onUpload,
                ),
            ],
          ),
        ),
        if (emojis.isEmpty)
          CircleCard(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                isSticker ? tr('No stickers yet') : tr('No emoji yet'),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ),
          )
        else
          SettingsGroup(
            separatorIndent: isSticker ? 84 : 66,
            children: [
              for (final emoji in emojis)
                Padding(
                  key: ValueKey('circle-emoji-${emoji.id}'),
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(
                    children: [
                      Container(
                        width: isSticker ? 58 : 40,
                        height: isSticker ? 58 : 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.well,
                          borderRadius: BorderRadius.circular(
                            isSticker ? WeCordRadii.md : WeCordRadii.sm,
                          ),
                        ),
                        child: CustomEmojiImage(
                          storagePath: emoji.storagePath,
                          size: isSticker ? 50 : 28,
                          semanticLabel: emoji.name,
                          fallback: Icon(
                            Icons.broken_image_outlined,
                            color: c.faint,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSticker ? emoji.name : ':${emoji.name}:',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            if (emoji.creatorName != null)
                              Text(
                                tr('Added by {name}', {
                                  'name': emoji.creatorName,
                                }),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canManage)
                        Builder(
                          builder: (buttonContext) => WeCordIconButton(
                            key: ValueKey('circle-emoji-menu-${emoji.id}'),
                            tooltip: tr('More'),
                            icon: Icons.more_horiz_rounded,
                            variant: WeCordButtonVariant.ghost,
                            size: 36,
                            onPressed: () {
                              final box =
                                  buttonContext.findRenderObject()
                                      as RenderBox?;
                              onMenu(
                                emoji,
                                box?.localToGlobal(
                                  box.size.bottomRight(Offset.zero),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
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
        _errorText = tr(
          'Use 2 to 32 lowercase letters, digits or underscores.',
        );
      });
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final colon = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: c.muted,
        ),
      ),
    );
    return CircleDialog(
      title: widget.title,
      content: WeCordTextField(
        fieldKey: const ValueKey('circle-emoji-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 32,
        label: tr('Name'),
        errorText: _errorText,
        suffix: colon,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('circle-emoji-name-submit'),
          label: widget.submitLabel,
          onPressed: _submit,
        ),
      ],
    );
  }
}
