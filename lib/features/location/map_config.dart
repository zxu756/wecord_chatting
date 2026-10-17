import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which map tiles and place search the app uses, set at build time:
///
/// ```
/// --dart-define=MAP_TILE_URL=https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=...
/// --dart-define=MAP_ATTRIBUTION="© MapTiler © OpenStreetMap contributors"
/// --dart-define=MAP_ATTRIBUTION_URL=https://www.maptiler.com/copyright/
/// --dart-define=GEOCODER_URL=https://nominatim.example.com
/// --dart-define=PLACES_URL=https://overpass.example.com/api/interpreter
/// ```
///
/// The defaults are OpenStreetMap's public servers, which are for light use
/// only (https://operations.osmfoundation.org/policies/tiles/): a production
/// deployment should switch to a provider with a key (MapTiler, Stadia, …)
/// or its own servers. See docs/location.md.
class MapConfig {
  const MapConfig({
    this.tileUrl = defaultTileUrl,
    this.attribution = defaultAttribution,
    this.attributionUrl = defaultAttributionUrl,
    this.geocoderUrl = defaultGeocoderUrl,
    this.placesUrl = defaultPlacesUrl,
    this.userAgent = defaultUserAgent,
    this.maxNativeZoom = 19,
  });

  /// The default tile server: OpenStreetMap's public one.
  static const defaultTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const defaultAttribution = '© OpenStreetMap contributors';
  static const defaultAttributionUrl =
      'https://www.openstreetmap.org/copyright';
  static const defaultGeocoderUrl = 'https://nominatim.openstreetmap.org';
  static const defaultPlacesUrl = 'https://overpass-api.de/api/interpreter';

  /// Identifies the app to the servers, as the OSM policies ask. (Browsers
  /// set their own User-Agent and send the page as Referer.)
  static const defaultUserAgent = 'WeCord/1.0 (https://wecord.jokebear.fyi)';

  /// The build's settings (`--dart-define`).
  factory MapConfig.fromEnvironment() {
    String pick(String value, String fallback) =>
        value.trim().isEmpty ? fallback : value.trim();
    return MapConfig(
      tileUrl: pick(
        const String.fromEnvironment('MAP_TILE_URL'),
        defaultTileUrl,
      ),
      attribution: pick(
        const String.fromEnvironment('MAP_ATTRIBUTION'),
        defaultAttribution,
      ),
      attributionUrl: pick(
        const String.fromEnvironment('MAP_ATTRIBUTION_URL'),
        defaultAttributionUrl,
      ),
      geocoderUrl: pick(
        const String.fromEnvironment('GEOCODER_URL'),
        defaultGeocoderUrl,
      ),
      placesUrl: pick(
        const String.fromEnvironment('PLACES_URL'),
        defaultPlacesUrl,
      ),
      userAgent: pick(
        const String.fromEnvironment('MAP_USER_AGENT'),
        defaultUserAgent,
      ),
    );
  }

  /// A tile URL template: `{z}`, `{x}`, `{y}` (and `{s}`, `{r}` where the
  /// provider has them).
  final String tileUrl;

  /// The credit that stays visible on every map.
  final String attribution;

  /// Where the credit links to.
  final String attributionUrl;

  /// A Nominatim server (search and reverse geocoding), without a trailing
  /// path.
  final String geocoderUrl;

  /// An Overpass API endpoint (places near a point).
  final String placesUrl;
  final String userAgent;

  /// The deepest zoom the tile server has pictures for.
  final int maxNativeZoom;

  /// Whether this is OpenStreetMap's public tile server, which asks to be
  /// used lightly.
  bool get usesPublicOsmTiles =>
      tileUrl.contains('tile.openstreetmap.org') ||
      tileUrl.contains('tile.osm.org');

  MapConfig copyWith({String? tileUrl, String? attribution}) {
    return MapConfig(
      tileUrl: tileUrl ?? this.tileUrl,
      attribution: attribution ?? this.attribution,
      attributionUrl: attributionUrl,
      geocoderUrl: geocoderUrl,
      placesUrl: placesUrl,
      userAgent: userAgent,
      maxNativeZoom: maxNativeZoom,
    );
  }
}

final mapConfigProvider = Provider<MapConfig>((ref) {
  return MapConfig.fromEnvironment();
});

/// Fetches the tiles. Tests replace it with one that draws them itself, so
/// no map test reaches the network.
final mapTileProviderProvider = Provider<TileProvider>((ref) {
  final config = ref.watch(mapConfigProvider);
  final provider = NetworkTileProvider(
    headers: {'User-Agent': config.userAgent},
    // Keeps tiles on disk where it can (not on the web, where the browser's
    // own cache serves), which is also what the OSM policy asks for.
    cachingProvider: kIsWeb
        ? null
        : BuiltInMapCachingProvider.getOrCreateInstance(),
  );
  ref.onDispose(provider.dispose);
  return provider;
});
