import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One image, zoomable: pinch or scroll to zoom, drag to pan when zoomed,
/// double-tap (or double-click) to zoom in at that spot and back out.
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
      _received = 0;
      _total = null;
    });
    final service = ref.read(filePreviewServiceProvider);
    final fetcher = ref.read(fileFetcherProvider);
    final cancel = _cancel = FetchCancel();
    try {
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
    final image = _image;
    if (image == null) {
      return _received > 0
          ? PreviewProgressView(file: file, received: _received, total: _total)
          : const PreviewSpinner();
    }
    return GestureDetector(
      key: ValueKey('image-preview-${file.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        panEnabled: _zoomed,
        clipBehavior: Clip.none,
        child: SizedBox.expand(
          child: Image(
            image: image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            semanticLabel: file.name,
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
        ),
      ),
    );
  }
}
