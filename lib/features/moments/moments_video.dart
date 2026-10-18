import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The video of a Moment: its poster frame with a play button and the
/// length. Tapping opens the chat's media viewer (play, pause, scrub, speed,
/// mute, full screen), which streams the file from the private bucket with a
/// signed link. The poster is the first frame the device made, so the feed
/// never downloads the video until someone plays it.
class MomentVideoTile extends StatelessWidget {
  const MomentVideoTile({required this.video, super.key});

  final MomentVideo video;

  /// What the viewer opens.
  PreviewFile get file => PreviewFile(
    bucket: momentsBucket,
    path: video.path,
    name: 'Moment.${video.path.split('.').last}',
    mimeType: video.mimeType,
    size: video.size,
    width: video.width > 0 ? video.width : null,
    height: video.height > 0 ? video.height : null,
  );

  @override
  Widget build(BuildContext context) {
    final ratio = (video.aspectRatio ?? 16 / 9).clamp(0.7, 1.8);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * (ratio < 1 ? 0.56 : 0.86);
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            key: const ValueKey('moment-video'),
            width: width,
            child: AspectRatio(
              aspectRatio: ratio,
              child: WeCordPressable(
                onPressed: () =>
                    unawaited(openFilePreview(context, file: file)),
                pressedScale: 0.98,
                semanticLabel: tr('Play video, {length}', {
                  'length': video.durationLabel,
                }),
                excludeSemantics: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                builder: (context, states) => ClipRRect(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MomentImage(path: video.poster),
                      const Center(child: MomentPlayBadge()),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: MomentLengthChip(label: video.durationLabel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A round play button over media. The scrim is a fixed dark tone on
/// purpose: it sits on a photo, not on a theme surface.
class MomentPlayBadge extends StatelessWidget {
  const MomentPlayBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        size: 34,
        color: Colors.white,
      ),
    );
  }
}

/// The length of a video, "0:42", over its poster.
class MomentLengthChip extends StatelessWidget {
  const MomentLengthChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
