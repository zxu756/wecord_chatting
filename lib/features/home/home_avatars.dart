import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
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

/// A friend's status as a small speech bubble above their avatar in the
/// friends row (Instagram Notes style): the emoji and the first
/// [FriendStatus.maxBubbleChars] characters, up to two lines. A tap opens
/// the chat and starts a reply to it ([onPressed]).
class StatusBubble extends StatelessWidget {
  const StatusBubble({
    required this.status,
    required this.name,
    required this.onPressed,
    super.key,
  });

  /// The most the bubble is tall: two short lines and its padding.
  static const height = 40.0;

  /// The dot under the bubble and its gap.
  static const tailHeight = 8.0;

  /// The room a row has to give a bubble.
  static const room = height + tailHeight;

  final FriendStatus status;

  /// Who it is from, as the viewer knows them.
  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: ValueKey('status-bubble-${status.userId}'),
      onPressed: onPressed,
      tooltip: tr('Reply to {name}\'s status', {'name': name}),
      semanticLabel: tr('{name}: {status}. Reply to the status.', {
        'name': name,
        'status': status.fullLabel,
      }),
      excludeSemantics: true,
      pressedScale: 0.95,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(
                maxHeight: height,
                maxWidth: 78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hovered ? c.raisedStrong : c.raised,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Text(
                status.bubbleLabel,
                key: ValueKey('status-bubble-text-${status.userId}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, height: 1.25, color: c.ink),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -1),
              child: Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: hovered ? c.raisedStrong : c.raised,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
