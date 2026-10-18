import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/features/stickers/add_sticker_sheet.dart';
import 'package:wecord/features/stickers/sticker_widgets.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> Chats -> My stickers.
void openStickerManagement(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => const StickerManagementScreen(),
    ),
  );
}

/// My stickers: the library, to add to (from a photo, with an optional
/// cut-out), arrange (drag a row, or use the reorder actions a screen reader
/// offers) and delete from. Stickers are private to the person; sending one
/// shares a copy with that chat only.
class StickerManagementScreen extends ConsumerStatefulWidget {
  const StickerManagementScreen({super.key});

  @override
  ConsumerState<StickerManagementScreen> createState() =>
      _StickerManagementScreenState();
}

class _StickerManagementScreenState
    extends ConsumerState<StickerManagementScreen> {
  /// The order just chosen, until the server's list has caught up.
  List<String>? _pending;

  /// Ids being deleted, hidden at once.
  final _deleting = <String>{};

  List<UserSticker> _arranged(List<UserSticker> stickers) {
    final visible = [
      for (final sticker in stickers)
        if (!_deleting.contains(sticker.id)) sticker,
    ];
    final pending = _pending;
    if (pending == null) {
      return visible;
    }
    if (listEquals([for (final sticker in visible) sticker.id], pending)) {
      _pending = null;
      return visible;
    }
    final byId = {for (final sticker in visible) sticker.id: sticker};
    return [
      for (final id in pending) ?byId[id],
      for (final sticker in visible)
        if (!pending.contains(sticker.id)) sticker,
    ];
  }

  void _snack(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _reorder(List<UserSticker> stickers, int from, int to) async {
    final next = [...stickers];
    next.insert(to, next.removeAt(from));
    final ids = [for (final sticker in next) sticker.id];
    setState(() => _pending = ids);
    try {
      await ref.read(userStickersRepositoryProvider).reorder(ids);
      ref.invalidate(userStickersProvider);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _pending = null);
      _snack(tr('Could not change the order. Try again.'));
    }
  }

  Future<void> _delete(UserSticker sticker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this sticker?')),
        content: Text(
          tr(
            'Messages that already sent it keep showing it. You can add it again from a chat.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('sticker-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _deleting.add(sticker.id));
    try {
      await ref.read(userStickersRepositoryProvider).delete(sticker);
      ref.invalidate(userStickersProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _deleting.remove(sticker.id));
        _snack(tr('Could not delete. Try again.'));
      }
    }
  }

  Future<void> _addFromPhotos() async {
    final image = await _pickPhoto();
    if (image == null || !mounted) {
      return;
    }
    final added = await showAddStickerSheet(context, source: () async => image);
    if (added) {
      _snack(tr('Added to your stickers.'));
    }
  }

  Future<Uint8List?> _pickPhoto() async {
    try {
      return (await ref.read(imagePickerServiceProvider).pickImage())?.bytes;
    } catch (error) {
      _snack(tr('Could not open the image. {error}', {'error': error}));
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final data = ref.watch(userStickersProvider);
    final loaded = data.value;
    final stickers = loaded == null ? const <UserSticker>[] : _arranged(loaded);
    final full = stickers.length >= maxUserStickers;
    return SettingsPage(
      title: tr('My stickers'),
      actions: [
        WeCordButton(
          key: const ValueKey('my-stickers-add'),
          label: tr('Add'),
          icon: Icons.add_rounded,
          size: WeCordButtonSize.small,
          variant: WeCordButtonVariant.accent,
          onPressed: full ? null : () => unawaited(_addFromPhotos()),
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
          child: Text(
            tr(
              'Keep pictures, GIFs and stickers from chats, or make one from a photo, and send them in any chat. They are private to you: a chat only gets the copy you send it.',
            ),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ),
        if (loaded == null && data.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (stickers.isEmpty)
          _EmptyStickers(onAdd: () => unawaited(_addFromPhotos()))
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Text(
              tr('{count} of {limit} stickers', {
                'count': stickers.length,
                'limit': maxUserStickers,
              }),
              key: const ValueKey('my-stickers-count'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
          _StickerList(
            stickers: stickers,
            onReorder: (from, to) => unawaited(_reorder(stickers, from, to)),
            onDelete: (sticker) => unawaited(_delete(sticker)),
          ),
        ],
      ],
    );
  }
}

class _StickerList extends StatelessWidget {
  const _StickerList({
    required this.stickers,
    required this.onReorder,
    required this.onDelete,
  });

  final List<UserSticker> stickers;
  final void Function(int from, int to) onReorder;
  final void Function(UserSticker sticker) onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        key: const ValueKey('my-stickers-list'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: stickers.length,
        onReorderItem: onReorder,
        proxyDecorator: (child, index, animation) => Material(
          color: c.panel,
          elevation: 0,
          shadowColor: Colors.transparent,
          child: child,
        ),
        itemBuilder: (context, index) {
          final sticker = stickers[index];
          return _StickerRow(
            key: ValueKey('my-sticker-row-${sticker.id}'),
            sticker: sticker,
            index: index,
            first: index == 0,
            onDelete: () => onDelete(sticker),
          );
        },
      ),
    );
  }
}

class _StickerRow extends StatelessWidget {
  const _StickerRow({
    required this.sticker,
    required this.index,
    required this.first,
    required this.onDelete,
    super.key,
  });

  final UserSticker sticker;
  final int index;
  final bool first;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final label = sticker.animated ? tr('Animated sticker') : tr('Sticker');
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: first ? null : Border(top: BorderSide(color: c.lineSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: StickerFileImage(
              file: StickerFile(userStickerBucket, sticker.path),
              size: 50,
              animated: sticker.animated,
              semanticLabel: label,
              fallback: Icon(Icons.broken_image_outlined, color: c.faint),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                Text(
                  '${sticker.width} × ${sticker.height}',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
            ),
          ),
          WeCordIconButton(
            key: ValueKey('my-sticker-delete-${sticker.id}'),
            tooltip: tr('Delete'),
            icon: Icons.delete_outline,
            variant: WeCordButtonVariant.ghost,
            size: 36,
            onPressed: onDelete,
          ),
          // The handle is for the mouse and the finger; a screen reader gets
          // "move up / move down" actions on the row instead.
          ExcludeSemantics(
            child: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 22,
                  color: c.faint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStickers extends StatelessWidget {
  const _EmptyStickers({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('my-stickers-empty'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        children: [
          const SettingsIconTile(
            icon: Icons.add_reaction_outlined,
            tone: SettingsTone.accent,
            size: 52,
          ),
          const SizedBox(height: 14),
          Text(
            tr('No stickers yet'),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Press and hold a picture, GIF or sticker in a chat and choose Add to stickers, or start from a photo.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
          ),
          const SizedBox(height: 16),
          WeCordButton(label: tr('Add from photos'), onPressed: onAdd),
        ],
      ),
    );
  }
}
