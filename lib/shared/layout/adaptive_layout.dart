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

/// From this width the app uses its desktop layout: the circle rail and a
/// sidebar stay on the left while pages change beside them.
const wideLayoutBreakpoint = 840.0;

/// Whether [width] calls for the desktop layout.
bool isWideLayout(double width) => width >= wideLayoutBreakpoint;

/// The longer side of the window from which a touch screen counts as a
/// tablet. No phone gets there (the largest are about 930 logical pixels
/// tall), and an iPad's Split View or Slide Over window keeps its full
/// height, so a narrow window still counts.
const tabletLongestSide = 960.0;

/// Whether to offer keyboard shortcuts: wherever input is not touch-first,
/// and on tablets, which often sit in a keyboard case.
bool usesKeyboardShortcuts(BuildContext context) {
  return !usesTouchInput(context) ||
      MediaQuery.sizeOf(context).longestSide >= tabletLongestSide;
}
