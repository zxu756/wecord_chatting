import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/ui/ui.dart';

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
    final c = context.tokens.colors;
    final siteName = preview.siteName ?? Uri.tryParse(preview.url)?.host;
    final imageUrl = preview.imageUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: WeCordPressable(
          key: const ValueKey('link-preview-card'),
          onPressed: () => _open(context, ref),
          pressedScale: 0.98,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          builder: (context, states) {
            final hovered = states.contains(WidgetState.hovered);
            return AnimatedContainer(
              duration: WeCordMotion.quick,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: hovered ? c.raised : c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
                border: Border.all(color: c.lineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imageUrl != null)
                    Image.network(
                      imageUrl,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox.shrink();
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (siteName != null && siteName.isNotEmpty)
                          Text(
                            siteName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.subtle,
                            ),
                          ),
                        if (preview.title case final title?) ...[
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: c.accentText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (preview.description case final description?) ...[
                          const SizedBox(height: 3),
                          Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    ref.read(linkLauncherProvider)(context, uri).catchError((Object _) {});
  }
}
