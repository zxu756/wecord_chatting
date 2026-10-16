import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A [PersonAvatar] (or, with [squircle], a [ThingAvatar] for groups) for
/// a stored avatar path or URL: resolves it to a display URL and shows the
/// initial on the name's color while there is none or it fails to load.
/// People get a [PresenceIndicator] (shape and color) on the corner.
class ResolvedAvatar extends ConsumerStatefulWidget {
  const ResolvedAvatar({
    required this.name,
    required this.avatarUrl,
    this.size = 46,
    this.presence,
    this.showPresence = false,
    this.ringColor,
    this.squircle = false,
    this.dotKey,
    super.key,
  });

  final String name;
  final String? avatarUrl;
  final double size;

  /// Null shows them offline (when [showPresence]).
  final PresenceStatus? presence;
  final bool showPresence;

  /// What the avatar sits on, cut around the presence dot.
  final Color? ringColor;

  /// A rounded square instead of a circle: groups, circles, bots.
  final bool squircle;

  final Key? dotKey;

  @override
  ConsumerState<ResolvedAvatar> createState() => _ResolvedAvatarState();
}

class _ResolvedAvatarState extends ConsumerState<ResolvedAvatar> {
  /// The URL that failed to load, so the initial shows instead.
  String? _failedUrl;
  String? _listenedUrl;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
    _listenedUrl = null;
  }

  /// Watches [image] for load errors (which would otherwise be reported as
  /// uncaught), falling back to the initial.
  void _listen(String url, ImageProvider image) {
    if (_listenedUrl == url) {
      return;
    }
    _stopListening();
    _listenedUrl = url;
    final stream = image.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (_, _) {},
      onError: (_, _) {
        if (mounted && _failedUrl != url) {
          setState(() => _failedUrl = url);
          refreshAvatarDisplayUrl(ref, widget.avatarUrl);
        }
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  Widget build(BuildContext context) {
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(widget.avatarUrl))
        .value;
    ImageProvider? image;
    if (displayUrl != null && displayUrl != _failedUrl) {
      image = NetworkImage(displayUrl);
      _listen(displayUrl, image);
    }
    if (widget.squircle) {
      return ThingAvatar(
        label: widget.name,
        size: widget.size,
        image: image,
        semanticLabel: widget.name,
      );
    }
    final ring = widget.ringColor ?? context.tokens.colors.panel;
    return PersonAvatar(
      name: widget.name,
      size: widget.size,
      image: image,
      ringColor: ring,
      badge: widget.showPresence
          ? PresenceIndicator(
              key: widget.dotKey,
              status: widget.presence,
              borderColor: ring,
              size: (widget.size * 0.3).clamp(12.0, 17.0),
            )
          : null,
    );
  }
}
