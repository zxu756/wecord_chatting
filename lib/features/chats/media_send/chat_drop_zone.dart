import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether files can be dragged onto the window here: on the web and on
/// macOS (the desktop platforms the app targets).
bool get dropIsSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Lets files be dropped onto the chat to attach them. While files are
/// dragged over it, a dashed frame and a card say "Drop to attach".
///
/// Phones have no drag and drop between apps in this build, so there the
/// child is returned as it is.
class ChatDropZone extends StatefulWidget {
  const ChatDropZone({
    required this.child,
    required this.onFiles,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// Called with the dropped files (folders are left out).
  final ValueChanged<List<XFile>> onFiles;
  final bool enabled;

  @override
  State<ChatDropZone> createState() => _ChatDropZoneState();
}

class _ChatDropZoneState extends State<ChatDropZone> {
  var _dragging = false;

  void _setDragging(bool value) {
    if (_dragging != value && mounted) {
      setState(() => _dragging = value);
    }
  }

  Future<void> _dropped(DropDoneDetails details) async {
    _setDragging(false);
    final files = <XFile>[];
    for (final item in details.files) {
      if (item is DropItemDirectory) {
        continue;
      }
      // Dropped files outside the app's sandbox on macOS need their
      // bookmark opened before they can be read. It stays open for the
      // life of the app: the file may be sent later.
      final bookmark = item.extraAppleBookmark;
      if (bookmark != null && bookmark.isNotEmpty) {
        try {
          await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        } on Object {
          // Reading it will tell.
        }
      }
      files.add(item);
    }
    if (files.isNotEmpty && mounted) {
      widget.onFiles(files);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!dropIsSupported) {
      return widget.child;
    }
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) => unawaited(_dropped(details)),
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_dragging && widget.enabled)
            const Positioned.fill(
              child: IgnorePointer(child: ChatDropOverlay()),
            ),
        ],
      ),
    );
  }
}

/// The frame and card shown while files are dragged over the chat.
class ChatDropOverlay extends StatelessWidget {
  const ChatDropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('chat-drop-overlay'),
      padding: const EdgeInsets.all(10),
      child: CustomPaint(
        foregroundPainter: _DashedFramePainter(
          color: c.accent,
          radius: WeCordRadii.xxl,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(WeCordRadii.xxl),
          ),
          child: Center(
            child: WeCordGlass(
              elevation: GlassElevation.menu,
              borderRadius: BorderRadius.circular(WeCordRadii.xl),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.upload_file_rounded,
                      size: 26,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Drop to attach'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('Photos, videos and files go in your next message.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedFramePainter extends CustomPainter {
  const _DashedFramePainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const dash = 10.0;
    const gap = 8.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFramePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
