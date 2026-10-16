import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A profile's banner card with its avatar overlapping the bottom left
/// edge on a ring of the surface color, and an optional [trailing] widget
/// (the status pill) at the bottom right. Without a banner image the card
/// is the person's color with soft light circles.
class ProfileBannerHeader extends ConsumerWidget {
  const ProfileBannerHeader({
    required this.bannerUrl,
    required this.avatar,
    this.colorSeed = '',
    this.bannerHeight = 130,
    this.avatarSize = 96,
    this.overlap = 52,
    this.trailing,
    this.ringColor,
    super.key,
  });

  /// A stored `profile-banners/…` path or an http(s) URL.
  final String? bannerUrl;
  final Widget avatar;

  /// Picks the card color when there is no image (the person's name).
  final String colorSeed;
  final double bannerHeight;

  /// The avatar's size, without its ring.
  final double avatarSize;

  /// How far the avatar (with its ring) reaches up into the banner.
  final double overlap;
  final Widget? trailing;

  /// The ring around the avatar: what the header sits on.
  final Color? ringColor;

  static const _ring = 6.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final displayUrl = ref
        .watch(avatarDisplayUrlProvider(bannerUrl))
        .valueOrNull;
    final outer = avatarSize + _ring * 2;
    final fill = WeCordAvatarColors.forSeed(colorSeed);
    return SizedBox(
      height: bannerHeight + outer - overlap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bannerHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WeCordRadii.xl),
              child: Container(
                key: const ValueKey('profile-banner'),
                color: fill,
                child: displayUrl == null
                    ? const CustomPaint(painter: _BannerLightsPainter())
                    : Image.network(
                        displayUrl,
                        key: const ValueKey('profile-banner-image'),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          refreshAvatarDisplayUrl(ref, bannerUrl);
                          return const CustomPaint(
                            painter: _BannerLightsPainter(),
                          );
                        },
                      ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: bannerHeight - overlap,
            child: Container(
              padding: const EdgeInsets.all(_ring),
              decoration: BoxDecoration(
                color: ringColor ?? c.panel,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(dimension: avatarSize, child: avatar),
            ),
          ),
          if (trailing != null)
            Positioned(
              left: outer + 20,
              right: 10,
              bottom: 8,
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
        ],
      ),
    );
  }
}

/// Two soft light circles over a plain banner.
class _BannerLightsPainter extends CustomPainter {
  const _BannerLightsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Light on a colored fill, like white text on an avatar.
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.15),
      46,
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      Offset(size.width * 0.10, size.height),
      70,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_BannerLightsPainter oldDelegate) => false;
}
