import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A person's [PersonAvatar] from a stored avatar path (signed when it is
/// private) or URL, falling back to the initial when the picture fails.
class ProfileAvatar extends ConsumerStatefulWidget {
  const ProfileAvatar({
    required this.name,
    required this.avatarUrl,
    this.size = 46,
    this.presence,
    this.presenceShape = PresenceShape.solid,
    this.presenceLabel,
    this.ringColor,
    this.badge,
    super.key,
  });

  final String name;

  /// A stored `avatars/…` path or an http(s) URL.
  final String? avatarUrl;
  final double size;

  /// The presence dot's color (see presenceColor).
  final Color? presence;

  /// The dot's shape and its words, so status doesn't rest on color alone.
  final PresenceShape presenceShape;
  final String? presenceLabel;
  final Color? ringColor;
  final Widget? badge;

  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  /// The URL that failed to load, so the initial shows instead.
  String? _failedUrl;

  @override
  Widget build(BuildContext context) {
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(widget.avatarUrl))
        .value;
    final image = displayUrl == null || displayUrl == _failedUrl
        ? null
        : NetworkImage(displayUrl);
    return PersonAvatar(
      name: widget.name,
      size: widget.size,
      image: image,
      presence: widget.presence,
      presenceShape: widget.presenceShape,
      presenceLabel: widget.presenceLabel,
      ringColor: widget.ringColor,
      badge: widget.badge,
      onImageError: image == null
          ? null
          : (_, _) {
              if (mounted && _failedUrl != displayUrl) {
                setState(() => _failedUrl = displayUrl);
                refreshAvatarDisplayUrl(ref, widget.avatarUrl);
              }
            },
    );
  }
}

/// A circle's or group's [ThingAvatar] from a stored path or URL, falling
/// back to the initial when the picture fails.
class StoredThingAvatar extends ConsumerStatefulWidget {
  const StoredThingAvatar({
    required this.label,
    required this.avatarUrl,
    this.size = 46,
    this.radius,
    super.key,
  });

  final String label;
  final String? avatarUrl;
  final double size;
  final double? radius;

  @override
  ConsumerState<StoredThingAvatar> createState() => _StoredThingAvatarState();
}

class _StoredThingAvatarState extends ConsumerState<StoredThingAvatar> {
  String? _failedUrl;

  @override
  Widget build(BuildContext context) {
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(widget.avatarUrl))
        .value;
    final image = displayUrl == null || displayUrl == _failedUrl
        ? null
        : NetworkImage(displayUrl);
    return ThingAvatar(
      label: widget.label,
      size: widget.size,
      radius: widget.radius,
      image: image,
      onImageError: image == null
          ? null
          : (_, _) {
              if (mounted && _failedUrl != displayUrl) {
                setState(() => _failedUrl = displayUrl);
              }
            },
    );
  }
}
