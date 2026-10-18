import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/map_config.dart';
import 'package:wecord/features/location/map_widgets.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The pixel matrix [darkModeTileBuilder] uses, to draw the tiles dark.
const _darkTiles = ColorFilter.matrix(<double>[
  0.5740000009536743, -1.4299999475479126, -0.14399999380111694, 0, 255, //
  -0.4259999990463257, -0.429999977350235, -0.14399999380111694, 0, 255, //
  -0.4259999990463257, -1.4299999475479126, 0.8559999465942383, 0, 255, //
  0, 0, 0, 1, 0, //
]);

/// A map that is only a picture: the few tiles around [center] drawn once
/// into a single repaint boundary, with the pin and the required credit.
///
/// It stands in for a live [FlutterMap] where a map is only a preview (the
/// location cards in a chat): no map state, layers, gestures or camera, so a
/// screen full of them scrolls like plain text. Tiles come from the same
/// configured server, provider and cache as [WeCordMap] ([MapConfig]), so the
/// tile URL, the headers and the attribution are the ones the app is set to.
class StaticMap extends ConsumerStatefulWidget {
  const StaticMap({
    required this.center,
    required this.width,
    required this.height,
    this.zoom = 15.5,
    this.pinSize = 44,
    this.attributionInsets = const EdgeInsets.fromLTRB(5, 0, 5, 5),
    super.key,
  });

  final LatLng center;
  final double width;
  final double height;
  final double zoom;

  /// The size of the pin laid on [center] (its tip is on the point).
  final double pinSize;
  final EdgeInsets attributionInsets;

  @override
  ConsumerState<StaticMap> createState() => _StaticMapState();
}

/// One tile of the picture: where it is and its image once it has loaded.
class _Slot {
  _Slot(this.coordinates, this.stream, this.listener, this.cancel);

  final TileCoordinates coordinates;
  final ImageStream stream;
  final ImageStreamListener listener;
  final Completer<void> cancel;
  ImageInfo? info;

  void dispose() {
    stream.removeListener(listener);
    if (!cancel.isCompleted) {
      cancel.complete();
    }
    info?.dispose();
    info = null;
  }
}

class _StaticMapState extends ConsumerState<StaticMap> {
  final _slots = <String, _Slot>{};
  var _revision = 0;
  String? _signature;

  /// What the loaded tiles came from: another server or provider means
  /// loading them again.
  String? _source;

  @override
  void dispose() {
    for (final slot in _slots.values) {
      slot.dispose();
    }
    _slots.clear();
    super.dispose();
  }

  /// The tiles the picture needs and where they fall, in the card's own
  /// pixels. Tiles of the zoom level nearest [StaticMap.zoom] are scaled the
  /// way the live map scales them.
  _Layout _layout(MapConfig config) {
    final zoom = widget.zoom;
    final tileZoom = zoom.round().clamp(0, config.maxNativeZoom);
    final scale = math.pow(2, zoom - tileZoom).toDouble();
    final worldSize = 256.0 * math.pow(2, tileZoom);
    final lat = widget.center.latitude.clamp(-85.05112878, 85.05112878);
    final sinLat = math.sin(lat * math.pi / 180);
    final worldX = (widget.center.longitude + 180) / 360 * worldSize;
    final worldY =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        worldSize;
    final left = worldX - widget.width / 2 / scale;
    final top = worldY - widget.height / 2 / scale;
    final right = worldX + widget.width / 2 / scale;
    final bottom = worldY + widget.height / 2 / scale;
    final count = 1 << tileZoom;
    final tiles = <TileCoordinates>[];
    for (var ty = (top / 256).floor(); ty <= (bottom / 256).floor(); ty++) {
      if (ty < 0 || ty >= count) {
        continue;
      }
      for (var tx = (left / 256).floor(); tx <= (right / 256).floor(); tx++) {
        tiles.add(TileCoordinates(tx, ty, tileZoom));
      }
    }
    return _Layout(
      tiles: tiles,
      left: left,
      top: top,
      scale: scale,
      tileZoom: tileZoom,
    );
  }

  /// Starts loading what is missing and lets go of what is no longer in the
  /// picture. Safe to call on every build: nothing happens unless the place,
  /// the size, the tile server or the provider changed.
  void _load(_Layout layout, MapConfig config, TileProvider provider) {
    final signature =
        '${config.tileUrl}|${identityHashCode(provider)}|'
        '${layout.tiles.map((t) => '${t.x},${t.y},${t.z}').join(';')}';
    if (signature == _signature) {
      return;
    }
    _signature = signature;
    final source = '${config.tileUrl}|${identityHashCode(provider)}';
    if (source != _source) {
      _source = source;
      for (final slot in _slots.values) {
        slot.dispose();
      }
      _slots.clear();
    }
    final options = TileLayer(
      urlTemplate: config.tileUrl,
      tileProvider: provider,
      maxNativeZoom: config.maxNativeZoom,
      userAgentPackageName: 'fyi.jokebear.wecord',
    );
    final wanted = <String>{};
    for (final coordinates in layout.tiles) {
      // The tile servers wrap sideways around the world.
      final count = 1 << coordinates.z;
      final wrapped = TileCoordinates(
        ((coordinates.x % count) + count) % count,
        coordinates.y,
        coordinates.z,
      );
      final key = '${wrapped.z}/${wrapped.x}/${wrapped.y}';
      wanted.add(key);
      if (_slots.containsKey(key)) {
        continue;
      }
      final cancel = Completer<void>();
      final image = provider.supportsCancelLoading
          ? provider.getImageWithCancelLoadingSupport(
              wrapped,
              options,
              cancel.future,
            )
          : provider.getImage(wrapped, options);
      final stream = image.resolve(ImageConfiguration.empty);
      late final _Slot slot;
      final listener = ImageStreamListener(
        (info, synchronous) {
          if (!identical(_slots[key], slot)) {
            info.dispose();
            return;
          }
          slot.info?.dispose();
          slot.info = info;
          _revision += 1;
          if (!synchronous && mounted) {
            setState(() {});
          }
        },
        // A tile that does not arrive leaves the plain background there.
        onError: (error, stackTrace) {},
      );
      slot = _Slot(wrapped, stream, listener, cancel);
      _slots[key] = slot;
      stream.addListener(listener);
    }
    for (final key in _slots.keys.where((k) => !wanted.contains(k)).toList()) {
      _slots.remove(key)?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(mapConfigProvider);
    final provider = ref.watch(mapTileProviderProvider);
    final c = context.tokens.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final layout = _layout(config);
    _load(layout, config, provider);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _TilesPainter(
                background: dark ? c.rail : c.raisedStrong,
                dark: dark,
                layout: layout,
                images: {
                  for (final slot in _slots.values)
                    if (slot.info != null)
                      '${slot.coordinates.z}/${slot.coordinates.x}/'
                              '${slot.coordinates.y}':
                          slot.info!.image,
                },
                revision: _revision,
              ),
            ),
          ),
          Positioned(
            left: widget.width / 2 - widget.pinSize / 2,
            top: widget.height / 2 - widget.pinSize,
            width: widget.pinSize,
            height: widget.pinSize,
            child: MapPin(size: widget.pinSize),
          ),
          Positioned(
            left: widget.attributionInsets.left,
            bottom: widget.attributionInsets.bottom,
            child: MapAttribution(
              text: config.attribution,
              url: config.attributionUrl,
            ),
          ),
        ],
      ),
    );
  }
}

class _Layout {
  const _Layout({
    required this.tiles,
    required this.left,
    required this.top,
    required this.scale,
    required this.tileZoom,
  });

  final List<TileCoordinates> tiles;

  /// The picture's top left corner in the world's pixels at [tileZoom].
  final double left;
  final double top;
  final double scale;
  final int tileZoom;
}

class _TilesPainter extends CustomPainter {
  _TilesPainter({
    required this.background,
    required this.dark,
    required this.layout,
    required this.images,
    required this.revision,
  });

  final Color background;
  final bool dark;
  final _Layout layout;
  final Map<String, ui.Image> images;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = dark ? _darkTiles : null;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final count = 1 << layout.tileZoom;
    for (final tile in layout.tiles) {
      final wrappedX = ((tile.x % count) + count) % count;
      final image = images['${tile.z}/$wrappedX/${tile.y}'];
      if (image == null) {
        continue;
      }
      final dx = (tile.x * 256 - layout.left) * layout.scale;
      final dy = (tile.y * 256 - layout.top) * layout.scale;
      final edge = 256 * layout.scale;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        // A touch of overlap hides the seams between scaled tiles.
        Rect.fromLTWH(dx, dy, edge + 0.5, edge + 0.5),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TilesPainter old) =>
      old.revision != revision ||
      old.dark != dark ||
      old.background != background ||
      old.layout.left != layout.left ||
      old.layout.top != layout.top ||
      old.layout.scale != layout.scale;
}
