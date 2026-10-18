import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/stickers/sticker_management_screen.dart';
import 'package:wecord/features/stickers/sticker_widgets.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The "Mine" tab of the sticker picker: the person's own stickers to send,
/// and a way to the management page. [onPick] gets the tapped sticker.
class MyStickersPanel extends ConsumerWidget {
  const MyStickersPanel({required this.onPick, super.key});

  final ValueChanged<UserSticker> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final stickers = ref.watch(userStickersProvider);
    final list = stickers.value;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (list.isEmpty) {
      return Padding(
        key: const ValueKey('my-stickers-panel-empty'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'No stickers of your own yet. Press and hold a picture, GIF or sticker in a chat and choose Add to stickers.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
            const SizedBox(height: 14),
            WeCordButton(
              key: const ValueKey('my-stickers-manage'),
              label: tr('Add from photos'),
              variant: WeCordButtonVariant.secondary,
              onPressed: () => _manage(context),
            ),
          ],
        ),
      );
    }
    return Flexible(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sticker in list)
                Semantics(
                  button: true,
                  label: sticker.animated
                      ? tr('Animated sticker')
                      : tr('Sticker'),
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('my-sticker-option-${sticker.id}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onPick(sticker),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: StickerFileImage(
                        file: StickerFile(userStickerBucket, sticker.path),
                        size: 88,
                        animated: sticker.animated,
                        fallback: const SizedBox.square(
                          dimension: 88,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                key: const ValueKey('my-stickers-manage'),
                onPressed: () => _manage(context),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(tr('Manage stickers')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the management page over the picker.
  void _manage(BuildContext context) => openStickerManagement(context);
}
