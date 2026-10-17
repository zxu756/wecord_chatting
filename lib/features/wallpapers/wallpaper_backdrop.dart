import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_painter.dart';
import 'package:wecord/features/wallpapers/wallpaper_presets.dart';
import 'package:wecord/shared/theme/glass_effects_controller.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';

/// The wash laid over a photo wallpaper, so bubbles keep their contrast
/// whatever the picture is.
///
/// Light theme: a neutral, mid-light veil, which lifts the darkest pixels
/// well clear of the (near black) outgoing bubble and takes the lightest
/// ones below the white incoming bubble. Dark theme: black at [dim], and
/// never less than [minPhotoDim].
Color wallpaperPhotoScrim(Brightness brightness, double dim) {
  if (brightness == Brightness.dark) {
    return Colors.black.withValues(
      alpha: dim.clamp(minPhotoDim, maxPhotoDim).toDouble(),
    );
  }
  return const Color(0xFFA8A59E).withValues(alpha: 0.38);
}

/// The surfaces messages are drawn on while a wallpaper is behind them. All
/// opaque (bubbles) or nearly so (the small pills of dates and system lines),
/// and chosen apart from the wallpapers' colors (see
/// `wallpaper_presets_test.dart`).
class WallpaperSurfaces {
  const WallpaperSurfaces._();

  /// Other people's bubbles: white on the light wallpapers, the raised
  /// graphite on the dark ones.
  static Color incomingBubble(WeCordTokens tokens) =>
      tokens.isDark ? tokens.colors.raised : tokens.colors.panel;

  /// My bubbles stay ink.
  static Color outgoingBubble(WeCordTokens tokens) => tokens.colors.ink;

  /// Dates, "new messages" and the typing line, which sit straight on the
  /// wallpaper.
  static Color pill(WeCordTokens tokens) =>
      (tokens.isDark ? tokens.colors.raised : tokens.colors.panel).withValues(
        alpha: 0.94,
      );

  /// A thin shadow that keeps a bubble's edge clear of any picture.
  static List<BoxShadow> bubbleShadow(WeCordTokens tokens) => [
    BoxShadow(
      color: (tokens.isDark ? Colors.black : tokens.colors.ink).withValues(
        alpha: tokens.isDark ? 0.35 : 0.12,
      ),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];
}

/// Whether wallpapers show at all here: not with the platform's high
/// contrast, and not with Glass effects (the app's reduced transparency)
/// turned off. They fall back to the plain background then.
bool wallpapersAllowed(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  if (media?.highContrast ?? false) {
    return false;
  }
  if (WeCordTokens.of(context).highContrast) {
    return false;
  }
  return WeCordAppearance.maybeOf(context)?.glassEffects ?? true;
}

/// What the chat below it is drawn over: the wallpaper, and so whether
/// bubbles and lines use their wallpaper surfaces ([active]).
class ChatWallpaperScope extends InheritedWidget {
  const ChatWallpaperScope({
    required this.wallpaper,
    required this.active,
    required super.child,
    this.photo,
    this.photoLoading = false,
    super.key,
  });

  final ChatWallpaper wallpaper;

  /// Whether a wallpaper is showing behind the messages.
  final bool active;
  final WallpaperPhoto? photo;

  /// The photo is on its way: a quiet placeholder shows.
  final bool photoLoading;

  /// Whether there is a wallpaper behind [context]'s messages.
  static bool activeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ChatWallpaperScope>()
          ?.active ??
      false;

  static ChatWallpaperScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatWallpaperScope>();

  @override
  bool updateShouldNotify(ChatWallpaperScope oldWidget) =>
      oldWidget.wallpaper != wallpaper ||
      oldWidget.active != active ||
      !identical(oldWidget.photo, photo) ||
      oldWidget.photoLoading != photoLoading;
}

/// Gives the chat below it its wallpaper: resolves the chat's own wallpaper
/// or the default, loads the photo, and applies the fallbacks.
class ChatWallpaperHost extends ConsumerWidget {
  const ChatWallpaperHost({
    required this.conversationId,
    required this.child,
    super.key,
  });

  final String conversationId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaper = ref.watch(chatWallpaperProvider(conversationId));
    final allowed = wallpapersAllowed(context);
    var active = false;
    WallpaperPhoto? photo;
    var loading = false;
    if (allowed && wallpaper.isPreset) {
      active = wallpaperPresetById(wallpaper.presetId) != null;
    } else if (allowed && wallpaper.isPhoto) {
      final async = ref.watch(wallpaperPhotoProvider(wallpaper.photoPath!));
      photo = async.value;
      loading = async.isLoading && photo == null;
      active = photo != null || loading;
    }
    return ChatWallpaperScope(
      wallpaper: wallpaper,
      active: active,
      photo: photo,
      photoLoading: loading,
      child: child,
    );
  }
}

/// The wallpaper itself, filling its parent: painted once behind the
/// scrolling messages (a repaint boundary keeps it out of their repaints).
/// Draws nothing when the scope has no wallpaper showing.
class ChatWallpaperBackdrop extends StatelessWidget {
  const ChatWallpaperBackdrop({
    this.edges = false,
    this.boundaryKey = const ValueKey('chat-wallpaper'),
    super.key,
  });

  /// The key of the repaint boundary the picture is painted in.
  final Key boundaryKey;

  /// Hairlines on the left and right edges: on desktop the chat sits
  /// between the sidebar and side panels, and the wallpaper must end
  /// cleanly against them.
  final bool edges;

  @override
  Widget build(BuildContext context) {
    final scope = ChatWallpaperScope.maybeOf(context);
    if (scope == null || !scope.active) {
      return const SizedBox.shrink();
    }
    final tokens = WeCordTokens.of(context);
    final brightness = tokens.brightness;
    final wallpaper = scope.wallpaper;
    final Widget picture;
    if (wallpaper.isPreset) {
      final preset = wallpaperPresetById(wallpaper.presetId);
      if (preset == null) {
        return const SizedBox.shrink();
      }
      picture = CustomPaint(
        painter: WallpaperPainter(preset: preset, brightness: brightness),
        isComplex: true,
        willChange: false,
        child: const SizedBox.expand(),
      );
    } else {
      picture = _PhotoWallpaper(
        wallpaper: wallpaper,
        photo: scope.photo,
        brightness: brightness,
      );
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          key: boundaryKey,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: edges
                ? BoxDecoration(
                    border: Border.symmetric(
                      vertical: BorderSide(color: tokens.colors.line),
                    ),
                  )
                : const BoxDecoration(),
            child: picture,
          ),
        ),
      ),
    );
  }
}

class _PhotoWallpaper extends StatelessWidget {
  const _PhotoWallpaper({
    required this.wallpaper,
    required this.photo,
    required this.brightness,
  });

  final ChatWallpaper wallpaper;
  final WallpaperPhoto? photo;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final scrim = wallpaperPhotoScrim(brightness, wallpaper.dim);
    // What shows while the photo loads: the scrim over a middle gray, so the
    // chat does not flash from the plain background to the picture.
    final placeholder = Color.alphaBlend(scrim, const Color(0xFF808080));
    final data = photo;
    return ColoredBox(
      color: placeholder,
      child: data == null
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, constraints) {
                final dpr = MediaQuery.devicePixelRatioOf(context);
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 400.0;
                final height = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : 800.0;
                // Decoded no bigger than the screen needs (it is cropped to
                // fill, so the smaller side decides the scale).
                final fill = math.max(width / data.width, height / data.height);
                final blurScale = wallpaper.blur ? 0.5 : 1.0;
                final cacheWidth = math.max(
                  64,
                  math.min(
                    data.width,
                    (data.width * fill * dpr * blurScale).ceil(),
                  ),
                );
                Widget image = Image(
                  image: ResizeImage(
                    MemoryImage(data.bytes),
                    width: cacheWidth,
                    allowUpscaling: false,
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment(wallpaper.focusX, wallpaper.focusY),
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  frameBuilder: (context, child, frame, synchronous) {
                    if (synchronous) {
                      return child;
                    }
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: WeCordMotion.durationOf(
                        context,
                        const Duration(milliseconds: 200),
                      ),
                      child: child,
                    );
                  },
                );
                if (wallpaper.blur) {
                  image = ClipRect(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 12,
                        sigmaY: 12,
                        tileMode: TileMode.clamp,
                      ),
                      // Scaled up a little, so the blur's soft edge falls
                      // outside the screen.
                      child: Transform.scale(scale: 1.08, child: image),
                    ),
                  );
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    ColoredBox(color: scrim),
                  ],
                );
              },
            ),
    );
  }
}

/// [child] on a small pill while a wallpaper is behind the chat, as it
/// stands: dates, "new messages" and the typing line sit straight on the
/// picture and need a surface of their own to stay readable.
class WallpaperPill extends StatelessWidget {
  const WallpaperPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!ChatWallpaperScope.activeOf(context)) {
      return child;
    }
    final tokens = WeCordTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WallpaperSurfaces.pill(tokens),
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
        boxShadow: WallpaperSurfaces.bubbleShadow(tokens),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
