import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart' show MatrixUtils;
import 'package:flutter/widgets.dart' show Matrix4;

/// The geometry of turning, cropping and fitting a picture. Pure functions
/// on sizes, rectangles and matrices.

/// The size of a [source] picture turned [quarterTurns] quarter turns.
Size rotatedSize(Size source, int quarterTurns) {
  return quarterTurns.isOdd ? Size(source.height, source.width) : source;
}

/// Maps a point of the picture (source pixels) to the same point of the
/// picture after [quarterTurns] clockwise quarter turns, whose top-left
/// corner is (0, 0) again.
Matrix4 sourceToRotated(Size source, int quarterTurns) {
  final w = source.width;
  final h = source.height;
  switch (quarterTurns % 4) {
    case 1:
      // (x, y) -> (h - y, x)
      return Matrix4(0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, h, 0, 0, 1);
    case 2:
      // (x, y) -> (w - x, h - y)
      return Matrix4(-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, w, h, 0, 1);
    case 3:
      // (x, y) -> (y, w - x)
      return Matrix4(0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, w, 0, 1);
    default:
      return Matrix4.identity();
  }
}

/// [rect], a part of a picture of size [before], after the picture is turned
/// a quarter turn clockwise.
Rect rotateRectClockwise(Rect rect, Size before) {
  final h = before.height;
  return Rect.fromLTRB(h - rect.bottom, rect.left, h - rect.top, rect.right);
}

/// The crop to use when going from [quarterTurns] to [quarterTurns] + 1.
Rect? rotateCropClockwise(Rect? crop, Size turned) =>
    crop == null ? null : rotateRectClockwise(crop, turned);

/// The size of the picture [crop] leaves of a turned picture of size
/// [turned], at most [maxEdge] on the long side (never enlarged).
Size outputSize(Size region, int maxEdge) {
  final longest = math.max(region.width, region.height);
  final scale = longest > maxEdge ? maxEdge / longest : 1.0;
  return Size(
    math.max(1, (region.width * scale).round()).toDouble(),
    math.max(1, (region.height * scale).round()).toDouble(),
  );
}

/// The ratios the crop can be fixed to. [free] has none.
enum CropRatio {
  free(null),
  square(1),
  fourThree(4 / 3),
  sixteenNine(16 / 9);

  const CropRatio(this.landscape);

  /// Width / height in landscape; null for free.
  final double? landscape;

  String get label => switch (this) {
    CropRatio.free => 'Free',
    CropRatio.square => '1:1',
    CropRatio.fourThree => '4:3',
    CropRatio.sixteenNine => '16:9',
  };

  /// The width / height to use, turned upright with [portrait].
  double? aspect({bool portrait = false}) {
    final value = landscape;
    if (value == null) {
      return null;
    }
    return portrait ? 1 / value : value;
  }
}

/// Which part of the crop a drag holds.
enum CropHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  move;

  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomLeft ||
      this == bottomRight;

  bool get movesLeft => this == topLeft || this == left || this == bottomLeft;
  bool get movesRight =>
      this == topRight || this == right || this == bottomRight;
  bool get movesTop => this == topLeft || this == top || this == topRight;
  bool get movesBottom =>
      this == bottomLeft || this == bottom || this == bottomRight;
}

/// The part of [rect] under [point], or null. Corners and edges count
/// within [reach] of the line; the inside moves the crop.
CropHandle? cropHandleAt(Rect rect, Offset point, {double reach = 24}) {
  final nearLeft = (point.dx - rect.left).abs() <= reach;
  final nearRight = (point.dx - rect.right).abs() <= reach;
  final nearTop = (point.dy - rect.top).abs() <= reach;
  final nearBottom = (point.dy - rect.bottom).abs() <= reach;
  final withinX =
      point.dx >= rect.left - reach && point.dx <= rect.right + reach;
  final withinY =
      point.dy >= rect.top - reach && point.dy <= rect.bottom + reach;
  if (nearTop && nearLeft) return CropHandle.topLeft;
  if (nearTop && nearRight) return CropHandle.topRight;
  if (nearBottom && nearLeft) return CropHandle.bottomLeft;
  if (nearBottom && nearRight) return CropHandle.bottomRight;
  // On a small crop the edges would swallow the inside; keep the inside
  // for moving when the rectangle is narrow.
  if (nearTop && withinX) return CropHandle.top;
  if (nearBottom && withinX) return CropHandle.bottom;
  if (nearLeft && withinY) return CropHandle.left;
  if (nearRight && withinY) return CropHandle.right;
  if (rect.contains(point)) return CropHandle.move;
  return null;
}

/// The crop after [handle] is dragged by [delta], from [start]. The result
/// stays inside [bounds], is at least [minSize] on each side, and keeps
/// [aspect] (width / height) when one is given.
Rect dragCrop(
  Rect start,
  CropHandle handle,
  Offset delta,
  Rect bounds, {
  double? aspect,
  double minSize = 48,
}) {
  final min = math.min(minSize, math.min(bounds.width, bounds.height));
  if (handle == CropHandle.move) {
    final dx = (start.left + delta.dx).clamp(
      bounds.left,
      bounds.right - start.width,
    );
    final dy = (start.top + delta.dy).clamp(
      bounds.top,
      bounds.bottom - start.height,
    );
    return Rect.fromLTWH(dx.toDouble(), dy.toDouble(), start.width, start.height);
  }
  var left = start.left;
  var top = start.top;
  var right = start.right;
  var bottom = start.bottom;
  if (handle.movesLeft) left += delta.dx;
  if (handle.movesRight) right += delta.dx;
  if (handle.movesTop) top += delta.dy;
  if (handle.movesBottom) bottom += delta.dy;

  if (aspect == null) {
    left = left.clamp(bounds.left, start.right - min).toDouble();
    right = right.clamp(start.left + min, bounds.right).toDouble();
    top = top.clamp(bounds.top, start.bottom - min).toDouble();
    bottom = bottom.clamp(start.top + min, bounds.bottom).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  // A fixed ratio: the opposite corner / edge stays put, the size follows
  // the drag as far as the ratio and the bounds allow.
  final anchorX = handle.movesLeft
      ? start.right
      : handle.movesRight
      ? start.left
      : start.center.dx;
  final anchorY = handle.movesTop
      ? start.bottom
      : handle.movesBottom
      ? start.top
      : start.center.dy;

  // The width the drag asks for.
  var width = right - left;
  var height = bottom - top;
  if (handle.isCorner) {
    // Follow whichever side moved more, in proportion.
    final byWidth = width;
    final byHeight = height * aspect;
    width = math.max(byWidth, byHeight);
  } else if (handle == CropHandle.top || handle == CropHandle.bottom) {
    width = height * aspect;
  }
  // (left / right: width as dragged.)

  // The largest width that fits the bounds from the anchor.
  double room;
  if (handle.isCorner) {
    final roomX = handle.movesLeft
        ? anchorX - bounds.left
        : bounds.right - anchorX;
    final roomY = handle.movesTop
        ? anchorY - bounds.top
        : bounds.bottom - anchorY;
    room = math.min(roomX, roomY * aspect);
  } else if (handle == CropHandle.left || handle == CropHandle.right) {
    final roomX = handle == CropHandle.left
        ? anchorX - bounds.left
        : bounds.right - anchorX;
    final double roomY =
        2.0 *
        math.min(
          start.center.dy - bounds.top,
          bounds.bottom - start.center.dy,
        );
    room = math.min(roomX, roomY * aspect);
  } else {
    final roomY = handle == CropHandle.top
        ? anchorY - bounds.top
        : bounds.bottom - anchorY;
    final double roomX =
        2.0 *
        math.min(
          start.center.dx - bounds.left,
          bounds.right - start.center.dx,
        );
    room = math.min(roomY * aspect, roomX);
  }
  final minWidth = math.max(min, min * aspect);
  width = width.clamp(math.min(minWidth, room), room).toDouble();
  height = width / aspect;

  if (handle.isCorner) {
    left = handle.movesLeft ? anchorX - width : anchorX;
    right = handle.movesLeft ? anchorX : anchorX + width;
    top = handle.movesTop ? anchorY - height : anchorY;
    bottom = handle.movesTop ? anchorY : anchorY + height;
  } else if (handle == CropHandle.left || handle == CropHandle.right) {
    left = handle == CropHandle.left ? anchorX - width : anchorX;
    right = handle == CropHandle.left ? anchorX : anchorX + width;
    top = start.center.dy - height / 2;
    bottom = start.center.dy + height / 2;
  } else {
    top = handle == CropHandle.top ? anchorY - height : anchorY;
    bottom = handle == CropHandle.top ? anchorY : anchorY + height;
    left = start.center.dx - width / 2;
    right = start.center.dx + width / 2;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// The biggest rectangle with [aspect] (width / height) that fits in
/// [within], centered on it.
Rect fitAspect(Rect within, double aspect) {
  var width = within.width;
  var height = width / aspect;
  if (height > within.height) {
    height = within.height;
    width = height * aspect;
  }
  return Rect.fromCenter(center: within.center, width: width, height: height);
}

/// Keeps [rect] inside [bounds] without changing its size (shrinking it if
/// it is bigger than the bounds).
Rect clampRect(Rect rect, Rect bounds) {
  final width = math.min(rect.width, bounds.width);
  final height = math.min(rect.height, bounds.height);
  final left = rect.left.clamp(bounds.left, bounds.right - width).toDouble();
  final top = rect.top.clamp(bounds.top, bounds.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

/// How a rectangle of [region] pixels is shown in a view of [view]: scaled
/// to fit, centered, then zoomed about the view's middle by [zoom] and
/// moved by [pan]. [regionToView] maps region coordinates to view
/// coordinates.
class ViewFit {
  const ViewFit({
    required this.view,
    required this.region,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.inset = 0,
  });

  final Size view;

  /// Space kept free around the picture at fit zoom (so the handles of a
  /// crop at the picture's edge can be grabbed).
  final double inset;

  /// The part of the (turned) picture shown, in the turned picture's pixels.
  final Rect region;
  final double zoom;
  final Offset pan;

  double get fitScale => region.isEmpty
      ? 1
      : math.max(
          0.0001,
          math.min(
            (view.width - 2 * inset) / region.width,
            (view.height - 2 * inset) / region.height,
          ),
        );

  double get scale => fitScale * zoom;

  /// Maps the turned picture's pixels to the view.
  Matrix4 get turnedToView {
    final s = scale;
    final center = Offset(view.width / 2, view.height / 2);
    // The region's middle lands on the view's middle (plus the pan).
    final dx = center.dx + pan.dx - region.center.dx * s;
    final dy = center.dy + pan.dy - region.center.dy * s;
    return Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
  }

  Offset toView(Offset turned) {
    final s = scale;
    return Offset(
      view.width / 2 + pan.dx + (turned.dx - region.center.dx) * s,
      view.height / 2 + pan.dy + (turned.dy - region.center.dy) * s,
    );
  }

  Offset toTurned(Offset viewPoint) {
    final s = scale;
    return Offset(
      region.center.dx + (viewPoint.dx - view.width / 2 - pan.dx) / s,
      region.center.dy + (viewPoint.dy - view.height / 2 - pan.dy) / s,
    );
  }

  /// Where [region] is drawn in the view.
  Rect get regionInView =>
      Rect.fromPoints(toView(region.topLeft), toView(region.bottomRight));

  /// A pan that keeps the picture from being dragged out of the view.
  Offset clampPan(Offset wanted) {
    final shown = regionInViewAtPan(Offset.zero);
    final limitX = math.max(0.0, (shown.width - view.width) / 2);
    final limitY = math.max(0.0, (shown.height - view.height) / 2);
    return Offset(
      wanted.dx.clamp(-limitX, limitX).toDouble(),
      wanted.dy.clamp(-limitY, limitY).toDouble(),
    );
  }

  Rect regionInViewAtPan(Offset p) => ViewFit(
    view: view,
    region: region,
    zoom: zoom,
    pan: p,
    inset: inset,
  ).regionInView;

  /// The zoom [newZoom] about the view point [focal], with the pan that
  /// keeps the point under [focal] where it is.
  ViewFit zoomedAbout(Offset focal, double newZoom) {
    final target = newZoom.clamp(1.0, maxZoom).toDouble();
    final turned = toTurned(focal);
    final next = ViewFit(
      view: view,
      region: region,
      zoom: target,
      pan: pan,
      inset: inset,
    );
    final moved = next.toView(turned);
    return ViewFit(
      view: view,
      region: region,
      zoom: target,
      pan: next.clampPan(pan + (focal - moved)),
      inset: inset,
    );
  }

  static const maxZoom = 8.0;
}

/// Applies a matrix to a point.
Offset transformPoint(Matrix4 matrix, Offset point) =>
    MatrixUtils.transformPoint(matrix, point);
