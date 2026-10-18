import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
import 'package:wecord/shared/api/signed_url_refresh.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A sticker's picture from a private bucket (the library, or a copy sent
/// to a chat), [size] square, scaled to fit. Shows [fallback] while there is
/// no picture (loading, gone). A sticker that [animated] holds still on its
/// first frame when the device asks for reduced motion.
class StickerFileImage extends ConsumerWidget {
  const StickerFileImage({
    required this.file,
    required this.size,
    required this.fallback,
    this.animated = false,
    this.semanticLabel,
    super.key,
  });

  final StickerFile file;
  final double size;
  final Widget fallback;
  final bool animated;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(stickerFileImageProvider(file));
    return switch (image) {
      AsyncData(value: final provider?) => MotionSafeImage(
        image: provider,
        animated: animated,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
        // Small enough to just hold still: no play button.
        playButton: false,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          // The cached signed URL may have expired: sign it again.
          refreshSignedUrlSoon('sticker:${file.bucket}/${file.path}', () {
            try {
              ref.invalidate(stickerFileImageProvider(file));
            } catch (_) {
              // The widget is gone; the next one to show it signs it.
            }
          });
          return fallback;
        },
      ),
      AsyncLoading() => SizedBox.square(dimension: size),
      _ => fallback,
    };
  }
}

/// A light checkerboard, so transparent parts of a sticker can be seen.
class StickerCheckerboard extends StatelessWidget {
  const StickerCheckerboard({
    required this.child,
    this.cell = 10,
    this.borderRadius = WeCordRadii.lg,
    super.key,
  });

  final Widget child;
  final double cell;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CustomPaint(
        painter: _CheckerPainter(c.well, c.raised, cell),
        child: child,
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter(this.dark, this.light, this.cell);

  final Color dark;
  final Color light;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final paint = Paint()..color = dark;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y % 2; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.dark != dark || old.light != light || old.cell != cell;
}
