import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/location/map_config.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The app's map: tiles from the configured server ([MapConfig]), the
/// required credit in the corner and whatever [children] lay over it
/// (markers, circles).
///
/// Dark mode draws the tiles inverted so the map does not glare.
class WeCordMap extends ConsumerWidget {
  const WeCordMap({
    required this.center,
    this.zoom = 15,
    this.controller,
    this.interactive = true,
    this.onPositionChanged,
    this.onTap,
    this.onMapReady,
    this.children = const [],
    this.attributionInsets = const EdgeInsets.fromLTRB(8, 0, 8, 8),
    this.showAttribution = true,
    this.initialCameraFit,
    super.key,
  });

  final LatLng center;
  final double zoom;
  final MapController? controller;
  final bool interactive;

  /// The camera moved; [hasGesture] is true when a finger or the mouse did
  /// it rather than the app.
  final void Function(MapCamera camera, bool hasGesture)? onPositionChanged;
  final void Function(LatLng point)? onTap;

  /// The map exists: its controller can move it from here on.
  final VoidCallback? onMapReady;

  /// Layers over the tiles ([MarkerLayer] and so on).
  final List<Widget> children;

  /// Where the credit sits: keep it clear of panels laid over the map.
  final EdgeInsets attributionInsets;
  final bool showAttribution;

  /// Fits the camera to these points at first instead of [center]/[zoom].
  final CameraFit? initialCameraFit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mapConfigProvider);
    final tiles = ref.watch(mapTileProviderProvider);
    final c = context.tokens.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The map is a picture: what it shows is also in words next to it
        // (the list of places, the cards, who is sharing).
        ExcludeSemantics(
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              initialCameraFit: initialCameraFit,
              minZoom: 2,
              maxZoom: 19,
              backgroundColor: dark ? c.rail : c.raisedStrong,
              interactionOptions: InteractionOptions(
                flags: interactive
                    ? InteractiveFlag.all & ~InteractiveFlag.rotate
                    : InteractiveFlag.none,
              ),
              onPositionChanged: onPositionChanged == null
                  ? null
                  : (camera, hasGesture) =>
                        onPositionChanged!(camera, hasGesture),
              onMapReady: onMapReady,
              onTap: onTap == null ? null : (_, point) => onTap!(point),
            ),
            children: [
              TileLayer(
                urlTemplate: config.tileUrl,
                tileProvider: tiles,
                maxNativeZoom: config.maxNativeZoom,
                userAgentPackageName: 'fyi.jokebear.wecord',
                tileBuilder: dark ? _darkTile : null,
              ),
              ...children,
            ],
          ),
        ),
        if (showAttribution)
          Positioned(
            left: attributionInsets.left,
            bottom: attributionInsets.bottom,
            child: MapAttribution(
              text: config.attribution,
              url: config.attributionUrl,
            ),
          ),
      ],
    );
  }

  static Widget _darkTile(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) => darkModeTileBuilder(context, tileWidget, tile);
}

/// The map credit the tile servers ask for, kept visible on every map. A
/// small chip; tapping it opens the provider's copyright page.
class MapAttribution extends StatelessWidget {
  const MapAttribution({required this.text, required this.url, super.key});

  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: const ValueKey('map-attribution'),
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } on Object {
            // No browser to open: the credit is still shown.
          }
        }
      },
      semanticLabel: tr('Map data: {credit}', {'credit': text}),
      hint: tr('Opens the copyright page'),
      pressedScale: 0.98,
      shape: const StadiumBorder(),
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.panel.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(WeCordRadii.pill),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
      ),
    );
  }
}

/// A round glass button floating over a map (back, my location, fit all).
class GlassMapButton extends StatelessWidget {
  const GlassMapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return WeCordGlass(
      borderRadius: BorderRadius.circular(size),
      child: WeCordIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        size: size,
        iconSize: 22,
        variant: WeCordButtonVariant.ghost,
        selected: selected,
      ),
    );
  }
}

/// The pin that marks a place. Its tip is at the bottom centre of the box,
/// so give the [Marker] an `Alignment.topCenter`.
class MapPin extends StatelessWidget {
  const MapPin({this.size = 48, this.lifted = false, super.key});

  final double size;

  /// Held up while the map is being dragged.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: 0,
              child: Container(
                width: size * 0.22,
                height: size * 0.08,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: lifted ? 0.1 : 0.28),
                  borderRadius: BorderRadius.circular(size),
                ),
              ),
            ),
            AnimatedPadding(
              duration: WeCordMotion.durationOf(context, WeCordMotion.quick),
              curve: WeCordMotion.standard,
              padding: EdgeInsets.only(
                bottom: lifted ? size * 0.2 : size * 0.04,
              ),
              child: Icon(
                Icons.location_on_rounded,
                size: size * 0.92,
                color: c.accent,
                shadows: const [
                  Shadow(blurRadius: 6, color: Color(0x40000000)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// This device's own position on a map: a blue dot with a white ring.
class MyLocationDot extends StatelessWidget {
  const MyLocationDot({this.size = 20, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x40000000))],
        ),
      ),
    );
  }
}

/// A person sharing, on the map: their picture in a ring, with their name
/// under it. Faded when their position is old (sharing paused).
class PersonMapMarker extends ConsumerWidget {
  const PersonMapMarker({
    required this.name,
    required this.avatarUrl,
    this.paused = false,
    this.isYou = false,
    this.size = 46,
    super.key,
  });

  final String name;
  final String? avatarUrl;
  final bool paused;
  final bool isYou;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final url = ref.watch(avatarDisplayUrlProvider(avatarUrl)).value;
    Widget face = PersonAvatar(name: name, size: size);
    if (url != null) {
      face = Stack(
        children: [
          face,
          ClipOval(
            child: Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    final ring = paused ? c.faint : (isYou ? c.accent : c.live);
    return Opacity(
      opacity: paused ? 0.6 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: ring,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(blurRadius: 8, color: Color(0x40000000)),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: c.panel, shape: BoxShape.circle),
              child: face,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            constraints: const BoxConstraints(maxWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.panel.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(WeCordRadii.pill),
            ),
            child: Text(
              isYou ? tr('You') : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rebuilds [builder] every [interval], for "5 s ago" and "12 min left".
class Ticker extends StatefulWidget {
  const Ticker({
    required this.builder,
    this.interval = const Duration(seconds: 5),
    super.key,
  });

  final WidgetBuilder builder;
  final Duration interval;

  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
