import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:wecord/features/later/later_cards.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/saved_note_image.dart';
import 'package:wecord/features/moments/moments_widgets.dart' show MomentImage;
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The icon of a kind of entry.
IconData savedKindIcon(SavedKind kind) => switch (kind) {
  SavedKind.message => Icons.bookmark_rounded,
  SavedKind.moment => Icons.photo_library_outlined,
  SavedKind.circlePost => Icons.dynamic_feed_outlined,
  SavedKind.link => Icons.link_rounded,
  SavedKind.note => Icons.sticky_note_2_outlined,
  SavedKind.text => Icons.notes_rounded,
};

/// "Moment", "Link"…: what kind of entry this is.
String savedKindLabel(SavedKind kind) => switch (kind) {
  SavedKind.message => tr('Message'),
  SavedKind.moment => tr('Moment'),
  SavedKind.circlePost => tr('Circle post'),
  SavedKind.link => tr('Link'),
  SavedKind.note => tr('Note'),
  SavedKind.text => tr('Note'),
};

/// The address of a link without "https://" and a trailing slash.
String savedLinkHost(String? url) {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null || uri.host.isEmpty) {
    return url ?? '';
  }
  final path = uri.path == '/' ? '' : uri.path;
  return '${uri.host}$path';
}

/// One saved entry on the Saved page: who or what it is, the text (or "no
/// longer visible"), the person's folder, tags and remark, and its actions.
class SavedCard extends StatelessWidget {
  const SavedCard({
    required this.item,
    required this.busy,
    required this.onOpen,
    required this.onToggleDone,
    required this.onRemove,
    required this.onEdit,
    this.place,
    this.folderName,
    this.onFolder,
    this.onTag,
    super.key,
  });

  final SavedMessage item;
  final bool busy;

  /// A message's place ("#general · Club"), or null.
  final String? place;
  final String? folderName;
  final VoidCallback onOpen;
  final VoidCallback onToggleDone;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final VoidCallback? onFolder;
  final ValueChanged<String>? onTag;

  bool get _opensNote =>
      item.kind == SavedKind.note || item.kind == SavedKind.text;

  String get _headline {
    switch (item.kind) {
      case SavedKind.message:
        return item.available && item.senderName.isNotEmpty
            ? item.senderName
            : tr('Message');
      case SavedKind.moment:
      case SavedKind.circlePost:
        return item.available && item.senderName.isNotEmpty
            ? item.senderName
            : savedKindLabel(item.kind);
      case SavedKind.link:
        final title = item.title?.trim() ?? '';
        return title.isNotEmpty ? title : savedLinkHost(item.url);
      case SavedKind.note:
      case SavedKind.text:
        final title = item.title?.trim() ?? '';
        return title.isNotEmpty ? title : tr('Note');
    }
  }

  String? get _subline {
    switch (item.kind) {
      case SavedKind.message:
        return place;
      case SavedKind.moment:
        final photos = (item.extra['photo_count'] as num?)?.toInt() ?? 0;
        return [
          savedKindLabel(item.kind),
          if (item.available && photos > 0)
            photos == 1
                ? tr('1 photo')
                : tr('{count} photos', {'count': photos}),
          if (item.available && item.extra['moment_kind'] == 'video')
            tr('Video'),
        ].join(' · ');
      case SavedKind.circlePost:
        final circle = item.extra['circle_name'] as String?;
        return [
          savedKindLabel(item.kind),
          if (circle != null && circle.isNotEmpty) circle,
        ].join(' · ');
      case SavedKind.link:
        return savedLinkHost(item.url);
      case SavedKind.note:
      case SavedKind.text:
        return null;
    }
  }

  String get _preview {
    switch (item.kind) {
      case SavedKind.message:
        return laterPreview(
          conversationId: item.conversationId ?? '',
          body: item.body,
          type: item.type,
        );
      case SavedKind.moment:
      case SavedKind.circlePost:
        if (item.body.trim().isNotEmpty) {
          return item.body;
        }
        return item.kind == SavedKind.circlePost
            ? switch (item.extra['attachment_kind']) {
                'image' => tr('Photo'),
                'file' => item.extra['attachment_name'] as String? ?? '',
                _ => '',
              }
            : '';
      case SavedKind.link:
        return '';
      case SavedKind.note:
      case SavedKind.text:
        return item.body;
    }
  }

  String get _openLabel => switch (item.kind) {
    SavedKind.message => tr('Jump'),
    SavedKind.moment => tr('Open'),
    SavedKind.circlePost => tr('Open circle'),
    SavedKind.link => tr('Open link'),
    SavedKind.note || SavedKind.text => tr('Open'),
  };

  Widget _leading(BuildContext context) {
    final c = context.tokens.colors;
    if (item.kind.isOwn) {
      return SettingsIconTile(
        icon: savedKindIcon(item.kind),
        tone: item.isDone ? SettingsTone.success : SettingsTone.accent,
        size: 46,
      );
    }
    return ProfileAvatar(
      name: _headline,
      avatarUrl: item.available ? item.senderAvatarUrl : null,
      badge: LaterAvatarBadge(
        color: item.isDone ? c.success : c.accent,
        icon: item.isDone ? Icons.check_rounded : savedKindIcon(item.kind),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final preview = _preview;
    final showBox = !item.available || preview.trim().isNotEmpty;
    final thumb = item.kind == SavedKind.moment && item.available
        ? item.extra['thumb'] as String?
        : null;
    final pictures = item.kind == SavedKind.note ? item.images : const [];
    final box = showBox
        ? LaterMessagePreview(
            available: item.available,
            text: preview,
            unavailableText: item.kind == SavedKind.message
                ? null
                : tr('No longer visible'),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (thumb != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 60,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                  child: MomentImage(path: thumb),
                ),
              ),
              if (box != null) ...[
                const SizedBox(width: 8),
                Expanded(child: box),
              ],
            ],
          )
        else
          ?box,
        if (pictures.isNotEmpty) ...[
          if (box != null) const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final image in pictures)
                SizedBox.square(
                  dimension: 60,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(WeCordRadii.md),
                    child: SavedNoteImage(
                      path: image.path,
                      semanticLabel: tr('Picture'),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final canOpen = item.available || item.kind.isOwn;
    final subline = _subline;
    final savedAt = describeWhen(
      MaterialLocalizations.of(context),
      item.savedAt.toLocal(),
      clock.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final remark = item.note?.trim() ?? '';
    final hasMeta = folderName != null || item.tags.isNotEmpty;
    return LaterCard(
      key: ValueKey('saved-${item.id}'),
      onPressed: canOpen ? (_opensNote ? onEdit : onOpen) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _leading(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                if (subline != null && subline.isNotEmpty)
                  Text(
                    subline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                const SizedBox(height: 8),
                _body(context),
                if (remark.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.edit_note_rounded,
                            size: 16,
                            color: c.muted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            remark,
                            key: ValueKey('saved-remark-${item.id}'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontStyle: FontStyle.italic,
                              color: c.muted,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (hasMeta)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (folderName != null)
                          WeCordChip(
                            key: ValueKey('saved-folder-of-${item.id}'),
                            label: folderName!,
                            icon: Icons.folder_outlined,
                            height: 28,
                            onPressed: onFolder,
                          ),
                        for (final tag in item.tags)
                          WeCordChip(
                            key: ValueKey('saved-tag-of-${item.id}-$tag'),
                            label: '#$tag',
                            height: 28,
                            onPressed: onTag == null ? null : () => onTag!(tag),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (item.available && !_opensNote)
                      WeCordButton(
                        key: ValueKey('saved-jump-${item.id}'),
                        label: _openLabel,
                        size: WeCordButtonSize.small,
                        variant: WeCordButtonVariant.secondary,
                        onPressed: onOpen,
                      ),
                    if (item.available || item.isDone)
                      WeCordButton(
                        key: ValueKey('saved-done-${item.id}'),
                        label: item.isDone ? tr('Undo') : tr('Mark done'),
                        icon: item.isDone
                            ? Icons.undo_rounded
                            : Icons.check_rounded,
                        size: WeCordButtonSize.small,
                        variant: item.isDone
                            ? WeCordButtonVariant.ghost
                            : WeCordButtonVariant.secondary,
                        loading: busy,
                        onPressed: busy ? null : onToggleDone,
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Saved {time}', {'time': savedAt}),
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ),
                    WeCordIconButton(
                      key: ValueKey('saved-edit-${item.id}'),
                      icon: Icons.edit_outlined,
                      tooltip: tr('Edit'),
                      variant: WeCordButtonVariant.ghost,
                      size: 36,
                      onPressed: busy ? null : onEdit,
                    ),
                    WeCordIconButton(
                      key: ValueKey('saved-remove-${item.id}'),
                      icon: Icons.bookmark_remove_outlined,
                      tooltip: tr('Remove from Saved'),
                      variant: WeCordButtonVariant.ghost,
                      size: 36,
                      onPressed: busy ? null : onRemove,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
