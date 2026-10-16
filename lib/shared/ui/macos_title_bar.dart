import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// Whether the app draws under a transparent macOS title bar (the native
/// macOS app; not the web app in a Mac browser).
bool get drawsUnderMacosTitleBar =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Space to keep clear at the top of the window for the traffic lights:
/// [WeCordSizes.macosTitleBar] in the native macOS app, else 0.
double get macosTitleBarInset =>
    drawsUnderMacosTitleBar ? WeCordSizes.macosTitleBar : 0;

const _windowChannel = MethodChannel('wecord/window');

/// Wraps the whole app in the native macOS app, where content runs under a
/// transparent title bar: reports the title bar as top padding (so app
/// bars and safe areas clear the traffic lights; the desktop shell removes
/// it again because its rail keeps them clear) and lays a
/// [MacosWindowDragArea] over the strip so the window can still be moved.
/// Elsewhere it is just its child.
class MacosTitleBarFrame extends StatelessWidget {
  const MacosTitleBarFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!drawsUnderMacosTitleBar) {
      return child;
    }
    final media = MediaQuery.of(context);
    const inset = WeCordSizes.macosTitleBar;
    return Stack(
      children: [
        MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              top: math.max(media.padding.top, inset),
            ),
            viewPadding: media.viewPadding.copyWith(
              top: math.max(media.viewPadding.top, inset),
            ),
          ),
          child: child,
        ),
        const Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: inset,
          child: MacosWindowDragArea(),
        ),
      ],
    );
  }
}

/// Makes the strip it covers drag the window in the native macOS app,
/// standing in for the hidden title bar. Lets taps through to what's
/// below, so it can lie over toolbars. Elsewhere it is just its child.
class MacosWindowDragArea extends StatelessWidget {
  const MacosWindowDragArea({this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!drawsUnderMacosTitleBar) {
      return child ?? const SizedBox.shrink();
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _windowChannel
          .invokeMethod<void>('startDrag')
          .catchError((Object _) {}),
      child: child,
    );
  }
}
