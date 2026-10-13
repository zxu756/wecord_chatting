import 'package:flutter/material.dart';

/// Below this width screens use their phone layout, e.g. app bars keep two
/// actions and move the rest into a More menu.
const compactWidthBreakpoint = 600.0;

/// Smallest tap target on touch screens (Apple asks for 44, Material 48).
const minTouchTargetSize = 44.0;

/// Whether [width] calls for the phone layout.
bool isCompactWidth(double width) => width < compactWidthBreakpoint;

/// Whether the app runs where fingers, not a mouse, are the main input. Also
/// true in mobile browsers, which report the phone's platform.
bool usesTouchInput(BuildContext context) {
  return switch (Theme.of(context).platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}
