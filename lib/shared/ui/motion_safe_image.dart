import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';
import 'package:wecord/shared/ui/wecord_pressable.dart';

/// Whether [url] or [mimeType] names an image format that can animate (GIF,
/// APNG). Used to decide where reduced motion applies and a play button is
/// worth showing.
bool isAnimatedImage({String? url, String? mimeType}) {
  final mime = mimeType?.toLowerCase();
  if (mime != null && (mime == 'image/gif' || mime == 'image/apng')) {
    return true;
  }
  if (url == null) {
    return false;
  }
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.endsWith('.gif') || path.endsWith('.apng');
}

/// An image that does not move when the platform asks for reduced motion:
/// an animated one (GIF) shows its first frame under a play button, and
/// plays only when the person taps it. Without reduced motion it is a plain
/// [Image].
///
/// Pass [animated] false for pictures that can't move (JPEG, PNG): they
/// always draw normally.
class MotionSafeImage extends StatefulWidget {
  const MotionSafeImage({
    required this.image,
    this.animated = true,
    this.width,
    this.height,
    this.fit,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.gaplessPlayback = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.playButton = true,
    super.key,
  });

  /// A network image.
  MotionSafeImage.network(
    String url, {
    bool? animated,
    this.width,
    this.height,
    this.fit,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.gaplessPlayback = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.playButton = true,
    super.key,
  }) : image = NetworkImage(url),
       animated = animated ?? isAnimatedImage(url: url);

  final ImageProvider image;

  /// Whether the picture can animate; see [isAnimatedImage].
  final bool animated;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// What a screen reader says about the picture ("GIF", "Image from Ada").
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final bool gaplessPlayback;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Whether a held picture shows a play button. Off for tiny pictures such
  /// as emoji, which just stay still.
  final bool playButton;

  @override
  State<MotionSafeImage> createState() => _MotionSafeImageState();
}

class _MotionSafeImageState extends State<MotionSafeImage> {
  var _playing = false;

  @override
  void didUpdateWidget(MotionSafeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _playing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hold =
        widget.animated && WeCordMotion.reduceMotion(context) && !_playing;
    if (!hold) {
      return Image(
        image: widget.image,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: widget.semanticLabel,
        excludeFromSemantics: widget.excludeFromSemantics,
        gaplessPlayback: widget.gaplessPlayback,
        loadingBuilder: widget.loadingBuilder,
        errorBuilder: widget.errorBuilder,
      );
    }
    final still = _FirstFrame(
      image: widget.image,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      semanticLabel: widget.semanticLabel,
      excludeFromSemantics: widget.excludeFromSemantics,
      errorBuilder: widget.errorBuilder,
    );
    if (!widget.playButton) {
      return still;
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        still,
        _PlayButton(onPressed: () => setState(() => _playing = true)),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      tooltip: tr('Play animation'),
      semanticLabel: tr('Play animation'),
      shape: const CircleBorder(),
      onPressed: onPressed,
      builder: (context, states) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.ink.withValues(alpha: 0.78),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.play_arrow_rounded, color: c.onInk, size: 26),
      ),
    );
  }
}

/// Draws only the first frame of [image].
class _FirstFrame extends StatefulWidget {
  const _FirstFrame({
    required this.image,
    this.width,
    this.height,
    this.fit,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.errorBuilder,
  });

  final ImageProvider image;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_FirstFrame> createState() => _FirstFrameState();
}

class _FirstFrameState extends State<_FirstFrame> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _frame;
  ({Object error, StackTrace? stack})? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_FirstFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _resolve();
    }
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) {
      return;
    }
    _stop();
    _frame?.dispose();
    _frame = null;
    _failure = null;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        // Keep the first frame, then stop listening so the stream pauses
        // there instead of running on.
        final frame = info.image.clone();
        final old = _frame;
        if (mounted) {
          setState(() => _frame = frame);
        } else {
          frame.dispose();
        }
        old?.dispose();
        _stream?.removeListener(listener);
        _listener = null;
      },
      onError: (error, stack) {
        if (mounted) {
          setState(() => _failure = (error: error, stack: stack));
        }
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _stop();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final builder = widget.errorBuilder;
    if (failure != null && builder != null) {
      return builder(context, failure.error, failure.stack);
    }
    final frame = _frame;
    final Widget picture = frame == null
        ? SizedBox(width: widget.width, height: widget.height)
        : RawImage(
            image: frame,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
          );
    if (widget.excludeFromSemantics || widget.semanticLabel == null) {
      return picture;
    }
    return Semantics(label: widget.semanticLabel, image: true, child: picture);
  }
}
