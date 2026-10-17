import 'package:flutter/material.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the pictures of a Moment full screen, starting at [initial].
Future<void> openMomentPhotos(
  BuildContext context,
  List<MomentPhoto> photos,
  int initial,
) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: WeCordMotion.durationOf(context, WeCordMotion.base),
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: MomentPhotoViewer(photos: photos, initial: initial),
      ),
    ),
  );
}

/// Full-screen pictures: swipe between them, pinch to zoom. The full-size
/// file is loaded, not the thumbnail.
class MomentPhotoViewer extends StatefulWidget {
  const MomentPhotoViewer({required this.photos, this.initial = 0, super.key});

  final List<MomentPhoto> photos;
  final int initial;

  @override
  State<MomentPhotoViewer> createState() => _MomentPhotoViewerState();
}

class _MomentPhotoViewerState extends State<MomentPhotoViewer> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initial.clamp(0, widget.photos.length - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('moment-photo-viewer'),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: MomentImage(
                path: widget.photos[index].path,
                contain: true,
                semanticLabel: tr('Photo {number} of {count}', {
                  'number': index + 1,
                  'count': widget.photos.length,
                }),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  WeCordIconButton(
                    key: const ValueKey('moment-photo-close'),
                    icon: Icons.close_rounded,
                    tooltip: tr('Close'),
                    size: 40,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (widget.photos.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: ShapeDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        '${_page + 1} / ${widget.photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
