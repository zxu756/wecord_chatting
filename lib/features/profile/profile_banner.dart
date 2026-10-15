import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_repository.dart';

/// A profile's banner with its avatar overlapping the bottom edge. Without
/// a banner image the strip is a plain theme colour.
class ProfileBannerHeader extends ConsumerWidget {
  const ProfileBannerHeader({
    required this.bannerUrl,
    required this.avatar,
    this.bannerHeight = 100,
    this.avatarRadius = 42,
    super.key,
  });

  /// A stored `profile-banners/…` path or an http(s) URL.
  final String? bannerUrl;
  final Widget avatar;
  final double bannerHeight;
  final double avatarRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(bannerUrl))
        .valueOrNull;
    return SizedBox(
      height: bannerHeight + avatarRadius,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bannerHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                key: const ValueKey('profile-banner'),
                color: colorScheme.surfaceContainerHighest,
                child: displayUrl == null
                    ? null
                    : Image.network(
                        displayUrl,
                        key: const ValueKey('profile-banner-image'),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          refreshAvatarDisplayUrl(ref, bannerUrl);
                          return const SizedBox.shrink();
                        },
                      ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 4),
              ),
              child: avatar,
            ),
          ),
        ],
      ),
    );
  }
}
