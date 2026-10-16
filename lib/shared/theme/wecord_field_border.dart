import 'package:flutter/material.dart';

/// The border of WeCord's filled inputs: a rounded rectangle drawn inside
/// the field (no line unless [borderSide] has one, e.g. the accent edge on
/// focus). Unlike [OutlineInputBorder] it is not an outline, so floating
/// labels stay inside the fill instead of cutting into the edge.
class WeCordFieldBorder extends InputBorder {
  const WeCordFieldBorder({
    super.borderSide = BorderSide.none,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final BorderRadius borderRadius;

  @override
  bool get isOutline => false;

  @override
  WeCordFieldBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
  }) {
    return WeCordFieldBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(
    borderSide.style == BorderStyle.none ? 0 : borderSide.width,
  );

  @override
  WeCordFieldBorder scale(double t) => WeCordFieldBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is WeCordFieldBorder) {
      return WeCordFieldBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is WeCordFieldBorder) {
      return WeCordFieldBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRRect(
      borderRadius
          .resolve(textDirection)
          .toRRect(rect)
          .deflate(borderSide.strokeInset),
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));
  }

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) {
    canvas.drawRRect(borderRadius.resolve(textDirection).toRRect(rect), paint);
  }

  @override
  bool get preferPaintInterior => true;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none) {
      return;
    }
    final outer = borderRadius.resolve(textDirection).toRRect(rect);
    canvas.drawRRect(
      outer.deflate(borderSide.strokeInset / 2),
      borderSide.toPaint(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WeCordFieldBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(borderSide, borderRadius);
}
