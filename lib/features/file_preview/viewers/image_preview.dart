import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One image, zoomable: pinch or scroll to zoom, drag to pan when zoomed,
/// double-tap (or double-click) to zoom in at that spot and back out.
/// SVGs are read into memory and drawn as vectors, sharp at any zoom.
/// On iOS and macOS it is downloaded into the file cache first (with
/// progress), so it opens instantly next time.
class ImagePreview extends ConsumerStatefulWidget {
  const ImagePreview({
    required this.file,
    required this.onTap,
    required this.onZoomChanged,
    this.onDownload,
    super.key,
  });

  final PreviewFile file;
  final VoidCallback onTap;

  /// Paging and swipe-to-close pause while zoomed in.
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback? onDownload;

  @override
  ConsumerState<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends ConsumerState<ImagePreview>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _zoomAnimation;
  Animation<Matrix4>? _zoomTween;
  Offset? _doubleTapAt;
  var _zoomed = false;

  ImageProvider? _image;

  /// The SVG's bytes, for vector files.
  Uint8List? _svg;
  Object? _error;
  var _received = 0;
  int? _total;
  FetchCancel? _cancel;

  @override
  void initState() {
    super.initState();
    _zoomAnimation = AnimationController(vsync: this)
      ..addListener(() {
        final tween = _zoomTween;
        if (tween != null) {
          _transform.value = tween.value;
        }
      });
    _transform.addListener(_onTransform);
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    _zoomAnimation.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _image = null;
      _svg = null;
      _received = 0;
      _total = null;
    });
    final service = ref.read(filePreviewServiceProvider);
    final fetcher = ref.read(fileFetcherProvider);
    final cancel = _cancel = FetchCancel();
    try {
      if (widget.file.kind == PreviewKind.svg) {
        final fetched = await fetcher.readBytes(
          widget.file,
          url: () => service.fileUrl(widget.file),
          maxBytes: maxSvgPreviewBytes,
          cancel: cancel,
          onProgress: (received, total) {
            if (mounted) {
              setState(() {
                _received = received;
                _total = total;
              });
            }
          },
        );
        if (fetched.truncated) {
          throw const FormatException('The SVG is too large to preview');
        }
        if (mounted) {
          setState(() => _svg = fetched.bytes);
        }
        return;
      }
      ImageProvider image;
      if (fetcher.cachesOnDisk) {
        final path = await fetcher.download(
          widget.file,
          url: () => service.fileUrl(widget.file),
          cancel: cancel,
          onProgress: (received, total) {
            if (mounted) {
              setState(() {
                _received = received;
                _total = total;
              });
            }
          },
        );
        image = platform.localFileImage(path);
      } else {
        image = NetworkImage((await service.fileUrl(widget.file)).toString());
      }
      if (mounted) {
        setState(() => _image = image);
      }
    } on FetchCancelledException {
      // Closed while loading.
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  void _animateTo(Matrix4 target) {
    final duration = WeCordMotion.smooth.durationOf(context);
    if (duration == Duration.zero) {
      _transform.value = target;
      return;
    }
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnimation, curve: WeCordMotion.smooth.curve),
    );
    _zoomAnimation
      ..duration = duration
      ..forward(from: 0);
  }

  void _onDoubleTap() {
    if (_zoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    final at = _doubleTapAt ?? Offset.zero;
    const scale = 2.6;
    final target = Matrix4.identity()
      ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if (_error != null) {
      return PreviewErrorView(
        file: file,
        onRetry: _load,
        onDownload: widget.onDownload,
      );
    }
    if (_svg case final svg?) {
      return _zoomable(
        file,
        SvgPicture.memory(
          svg,
          key: ValueKey('svg-preview-${file.key}'),
          fit: BoxFit.contain,
          // The page names the picture (see _zoomable).
          excludeFromSemantics: true,
          placeholderBuilder: (context) => const PreviewSpinner(),
          errorBuilder: (context, error, stackTrace) => PreviewErrorView(
            file: file,
            onRetry: _load,
            onDownload: widget.onDownload,
          ),
        ),
      );
    }
    final image = _image;
    if (image == null) {
      return _received > 0
          ? PreviewProgressView(file: file, received: _received, total: _total)
          : const PreviewSpinner();
    }
    return _zoomable(
      file,
      // A GIF stands still on its first frame under reduced motion, with a
      // play button.
      MotionSafeImage(
        image: image,
        animated: isAnimatedImage(url: file.name, mimeType: file.mimeType),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, sync) {
          if (frame == null && !sync) {
            return const PreviewSpinner();
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) => PreviewErrorView(
          file: file,
          onRetry: () {
            unawaited(image.evict());
            unawaited(_load());
          },
          onDownload: widget.onDownload,
        ),
      ),
    );
  }

  /// [child] filling the page, with pinch, scroll and double-tap zoom.
  Widget _zoomable(PreviewFile file, Widget child) {
    // The page is one control for a screen reader: the picture's name, and
    // a tap that shows or hides the viewer's controls.
    return Semantics(
      container: true,
      // The sender's description when there is one, else the file's name.
      label: file.alt ?? file.name,
      image: true,
      hint: tr('Tap to show or hide the controls'),
      onTap: widget.onTap,
      child: GestureDetector(
        key: ValueKey('image-preview-${file.key}'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onTap,
        onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 6,
          panEnabled: _zoomed,
          clipBehavior: Clip.none,
          child: SizedBox.expand(child: child),
        ),
      ),
    );
  }
}
