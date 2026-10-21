import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/events2/event_manage_sheet.dart';
import 'package:wecord/features/events2/event_widgets.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The pictures people added to an event, newest first.
final eventPhotosProvider = FutureProvider.autoDispose
    .family<List<EventPhoto>, EventRef>((ref, key) {
      return ref
          .watch(events2RepositoryProvider)
          .listPhotos(key.kind, key.eventId);
    });

/// The event's own album: pictures of the people who took part, collected in
/// one place from an hour before the start. Hidden until the event has
/// started, unless it already has some.
class EventPhotosSection extends ConsumerWidget {
  const EventPhotosSection({
    required this.kind,
    required this.eventId,
    required this.scopeId,
    required this.started,
    required this.photoCount,
    super.key,
  });

  final EventKind kind;
  final String eventId;
  final String scopeId;

  /// Whether the event has started (or is about to).
  final bool started;
  final int photoCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!started && photoCount == 0) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final key = (kind: kind, eventId: eventId);
    final photos = ref.watch(eventPhotosProvider(key));

    Future<void> add() async {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (image == null || !context.mounted) {
        return;
      }
      final ok = await runEventAction(
        context,
        () => ref
            .read(events2RepositoryProvider)
            .addPhoto(kind, eventId, scopeId, image),
      );
      if (ok) {
        ref.invalidate(eventPhotosProvider(key));
      }
    }

    return Column(
      key: const ValueKey('event-photos'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  photos.value == null
                      ? tr('Pictures')
                      : tr('Pictures ({count})', {
                          'count': photos.value!.length,
                        }),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ),
            ),
            if (started)
              WeCordButton(
                key: const ValueKey('event-photo-add'),
                label: tr('Add a picture'),
                icon: Icons.add_photo_alternate_outlined,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: () => unawaited(add()),
              ),
          ],
        ),
        const SizedBox(height: 8),
        photos.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => Text(
            tr('Could not load the pictures.'),
            style: TextStyle(fontSize: 13.5, color: c.muted),
          ),
          data: (list) => list.isEmpty
              ? Text(
                  started
                      ? tr('No pictures yet. Add the first one.')
                      : tr('No pictures yet.'),
                  style: TextStyle(fontSize: 13.5, color: c.muted),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final photo = list[index];
                    return WeCordPressable(
                      key: ValueKey('event-photo-${photo.id}'),
                      semanticLabel: photo.uploaderName.isEmpty
                          ? tr('Picture')
                          : tr('Picture by {name}', {
                              'name': photo.uploaderName,
                            }),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(WeCordRadii.md),
                      ),
                      onPressed: () =>
                          unawaited(_showPhoto(context, ref, photo, key)),
                      builder: (context, states) => ClipRRect(
                        borderRadius: BorderRadius.circular(WeCordRadii.md),
                        child: EventPicture(
                          bucket: photo.bucket,
                          path: photo.path,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showPhoto(
    BuildContext context,
    WidgetRef ref,
    EventPhoto photo,
    EventRef key,
  ) {
    return showDialog<void>(
      context: context,
      barrierColor: context.tokens.colors.scrim,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.7,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: EventPicture(
                    bucket: photo.bucket,
                    path: photo.path,
                    semanticLabel: tr('Event picture'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (photo.uploaderName.isNotEmpty)
                  Expanded(
                    child: Text(
                      tr('Added by {name}', {'name': photo.uploaderName}),
                      style: const TextStyle(color: Colors.white),
                    ),
                  )
                else
                  const Spacer(),
                if (photo.canDelete)
                  WeCordButton(
                    key: const ValueKey('event-photo-delete'),
                    label: tr('Delete'),
                    icon: Icons.delete_outline_rounded,
                    variant: WeCordButtonVariant.secondary,
                    size: WeCordButtonSize.small,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      final ok = await runEventAction(
                        context,
                        () => ref
                            .read(events2RepositoryProvider)
                            .deletePhoto(photo),
                      );
                      if (ok) {
                        ref.invalidate(eventPhotosProvider(key));
                      }
                    },
                  ),
                const SizedBox(width: 8),
                WeCordButton(
                  label: tr('Close'),
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
