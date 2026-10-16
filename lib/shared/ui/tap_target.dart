import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// The smallest touch target on [platform]: Material asks for 48 on
/// Android, Apple's guidelines for 44 on iOS. Zero where a mouse and
/// keyboard are the main input (macOS, Windows, Linux).
double touchTargetFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android || TargetPlatform.fuchsia => 48,
  TargetPlatform.iOS => WeCordSizes.touchTarget,
  TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => 0,
};

extension WeCordTouchTargetTheme on ThemeData {
  /// The smallest touch target for this theme's platform (0 on desktops).
  double get platformTouchTarget => touchTargetFor(platform);
}

extension WeCordTouchTargetContext on BuildContext {
  /// The smallest touch target for the platform here (0 on desktops).
  double get touchTargetSize => touchTargetFor(Theme.of(this).platform);
}

/// Grows its child's tappable (and accessibility) area to at least [minSize]
/// without changing how it looks: the child is centred in the extra space
/// and a tap anywhere in it reaches the child. Does nothing for a child
/// that is already big enough, or when [minSize] is zero.
///
/// The extra space is real layout space (like Material's padded tap target
/// size), so a 32-high pill takes 44–48 of height on phones.
class WeCordTapTarget extends SingleChildRenderObjectWidget {
  const WeCordTapTarget({required this.minSize, super.child, super.key});

  /// Both sides of the smallest area, e.g. 44 or 48.
  final Size minSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTapTarget(minSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderTapTarget).minSize = minSize;
  }
}

class _RenderTapTarget extends RenderShiftedBox {
  _RenderTapTarget(this._minSize) : super(null);

  Size _minSize;

  set minSize(Size value) {
    if (_minSize != value) {
      _minSize = value;
      markNeedsLayout();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(super.computeMinIntrinsicWidth(height), _minSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(super.computeMaxIntrinsicWidth(height), _minSize.width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width), _minSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width), _minSize.height);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) {
      return constraints.constrain(_minSize);
    }
    final childSize = child.getDryLayout(constraints);
    return constraints.constrain(
      Size(
        math.max(childSize.width, _minSize.width),
        math.max(childSize.height, _minSize.height),
      ),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(_minSize);
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        math.max(child.size.width, _minSize.width),
        math.max(child.size.height, _minSize.height),
      ),
    );
    final data = child.parentData! as BoxParentData;
    data.offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final child = this.child;
    final distance = child?.getDistanceToActualBaseline(baseline);
    if (distance == null) {
      return null;
    }
    return distance + (child!.parentData! as BoxParentData).offset.dy;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) {
      return true;
    }
    final child = this.child;
    if (child == null || !size.contains(position)) {
      return false;
    }
    // A tap in the extra space counts as a tap in the middle of the child.
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (BoxHitTestResult result, Offset position) =>
          child.hitTest(result, position: center),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Size>('minSize', _minSize));
  }
}
