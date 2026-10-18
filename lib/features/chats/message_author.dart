import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/display_size_image.dart';

/// A round avatar for [avatarUrl] (an http(s) URL or a stored avatar path)
/// that shows [title]'s initials when there is no image or it fails to load.
class FallbackAvatar extends ConsumerStatefulWidget {
  const FallbackAvatar({
    required this.title,
    required this.avatarUrl,
    this.radius,
    super.key,
  });

  final String title;
  final String? avatarUrl;
  final double? radius;

  @override
  ConsumerState<FallbackAvatar> createState() => _FallbackAvatarState();
}

class _FallbackAvatarState extends ConsumerState<FallbackAvatar> {
  /// The URL that failed to load, so the initials show instead.
  String? _failedUrl;

  @override
  Widget build(BuildContext context) {
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(widget.avatarUrl))
        .value;
    final image = displayUrl == null || displayUrl == _failedUrl
        ? null
        : avatarImageFor(
            NetworkImage(displayUrl),
            size: (widget.radius ?? 20) * 2,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
    return CircleAvatar(
      radius: widget.radius,
      backgroundImage: image,
      onBackgroundImageError: image == null
          ? null
          : (_, _) {
              if (mounted && _failedUrl != displayUrl) {
                setState(() => _failedUrl = displayUrl);
                refreshAvatarDisplayUrl(ref, widget.avatarUrl);
              }
            },
      child: image == null ? Text(avatarInitials(widget.title)) : null,
    );
  }
}

/// The small "BOT" label next to a webhook's name.
class MessageBotTag extends StatelessWidget {
  const MessageBotTag({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('message-bot-tag'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr('BOT'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Up to two initials of [value], or `?`.
String avatarInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}
