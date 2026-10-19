import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How a signed link becomes a picture (a network image; tests show
/// pictures from memory).
final savedImageProviderFactory = Provider<ImageProvider Function(String)>(
  (ref) =>
      (url) => NetworkImage(url),
);

/// A signed link to a picture of a note, reused while it is valid.
final savedNoteImageUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) {
      final repository = ref.watch(savedMessagesRepositoryProvider);
      return ref
          .watch(chatSignedUrlCacheProvider)
          .get(
            SignedUrlCache.keyFor(savedNotesBucket, path),
            () => repository.signedUrl(path),
          );
    });

/// A picture of a note, read from its private bucket.
class SavedNoteImage extends ConsumerStatefulWidget {
  const SavedNoteImage({
    required this.path,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  ConsumerState<SavedNoteImage> createState() => _SavedNoteImageState();
}

class _SavedNoteImageState extends ConsumerState<SavedNoteImage> {
  var _retried = false;

  void _retry() {
    if (_retried) {
      return;
    }
    _retried = true;
    // The link may have expired: sign it again once.
    ref
        .read(chatSignedUrlCacheProvider)
        .evict(SignedUrlCache.keyFor(savedNotesBucket, widget.path));
    ref.invalidate(savedNoteImageUrlProvider(widget.path));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget placeholder([IconData? icon]) => ColoredBox(
      color: c.raised,
      child: icon == null
          ? null
          : Center(child: Icon(icon, size: 22, color: c.faint)),
    );
    return ref
        .watch(savedNoteImageUrlProvider(widget.path))
        .when(
          loading: placeholder,
          error: (error, stackTrace) =>
              placeholder(Icons.broken_image_outlined),
          data: (url) => Image(
            image: ref.read(savedImageProviderFactory)(url),
            fit: widget.fit,
            semanticLabel: widget.semanticLabel,
            excludeFromSemantics: widget.semanticLabel == null,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder(),
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _retry();
                }
              });
              return placeholder(Icons.broken_image_outlined);
            },
          ),
        );
  }
}
