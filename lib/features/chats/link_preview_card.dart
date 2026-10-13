import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/shared/models/link_preview.dart';

/// Previews stay cached for the session, so scrolling never refetches them.
/// Failures resolve to null and render nothing.
final linkPreviewProvider = FutureProvider.family<LinkPreview?, String>((
  ref,
  url,
) async {
  try {
    return await ref.watch(chatsRepositoryProvider).getLinkPreview(url);
  } catch (_) {
    return null;
  }
});

/// The card under a message for its first link; empty until the preview
/// loads and when there is none.
class MessageLinkPreviewCard extends ConsumerWidget {
  const MessageLinkPreviewCard({
    required this.url,
    this.bottomGap = 8,
    super.key,
  });

  final String url;
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(linkPreviewProvider(url)).valueOrNull;
    if (preview == null || !preview.hasContent) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final siteName = preview.siteName ?? Uri.tryParse(preview.url)?.host;
    final imageUrl = preview.imageUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Material(
          key: const ValueKey('link-preview-card'),
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(ref),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 4),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (siteName != null && siteName.isNotEmpty)
                    Text(
                      siteName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (preview.title case final title?) ...[
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (preview.description case final description?) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                  if (imageUrl != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        imageUrl,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(WidgetRef ref) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    ref.read(linkLauncherProvider)(uri).catchError((Object _) {});
  }
}
