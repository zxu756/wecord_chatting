import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/map_config.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Searching places, naming a spot and listing what is near it fails (no
/// network, the server said no, too many requests).
class PlacesUnavailable implements Exception {
  const PlacesUnavailable([this.reason]);

  final String? reason;

  @override
  String toString() => 'PlacesUnavailable(${reason ?? ''})';
}

/// Place lookups for the location picker.
///
/// The app uses Nominatim for search and for naming a spot, and Overpass for
/// "places near here" (both OpenStreetMap data, both configurable, see
/// [MapConfig]). The public servers allow one request a second and ask for
/// an identifying User-Agent and caching, which [NominatimPlacesService]
/// keeps to. Apple's MapKit search (a native plugin on iOS and macOS) would
/// give richer results there, but it does not exist on the web and could
/// not be exercised without a device, so one code path serves every
/// platform.
abstract interface class PlacesService {
  /// Places matching [query], the closest to [near] first when it is given.
  Future<List<PlaceInfo>> search(String query, {LatLng? near});

  /// Named places within a few hundred meters of [point], nearest first.
  Future<List<PlaceInfo>> nearby(LatLng point);

  /// What is at [point]: its name (a shop, a landmark) when it has one and
  /// its address. Null when the server knows nothing there.
  Future<PlaceInfo?> reverse(LatLng point);
}

/// Spaces requests at least [gap] apart, in the order they came.
class RequestSpacer {
  RequestSpacer({this.gap = const Duration(milliseconds: 1100)});

  final Duration gap;
  DateTime? _next;

  /// Completes when it is this caller's turn.
  Future<void> turn() {
    final now = clock.now();
    final start = _next == null || _next!.isBefore(now) ? now : _next!;
    _next = start.add(gap);
    final wait = start.difference(now);
    return wait > Duration.zero ? Future<void>.delayed(wait) : Future.value();
  }
}

class _Lru<K, V> {
  _Lru(this.capacity);

  final int capacity;
  final _map = <K, V>{};

  V? operator [](K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }
}

class NominatimPlacesService implements PlacesService {
  NominatimPlacesService({
    required this.config,
    http.Client? client,
    RequestSpacer? nominatimSpacer,
    RequestSpacer? overpassSpacer,
    bool? sendUserAgent,
  }) : _client = client ?? http.Client(),
       _nominatim = nominatimSpacer ?? RequestSpacer(),
       _overpass =
           overpassSpacer ??
           RequestSpacer(gap: const Duration(milliseconds: 2000)),
       _sendUserAgent = sendUserAgent ?? !kIsWeb;

  final MapConfig config;
  final http.Client _client;
  final RequestSpacer _nominatim;
  final RequestSpacer _overpass;
  final bool _sendUserAgent;

  final _reverseCache = _Lru<String, PlaceInfo?>(64);
  final _searchCache = _Lru<String, List<PlaceInfo>>(32);
  final _nearbyCache = _Lru<String, List<PlaceInfo>>(16);

  Map<String, String> get _headers => {
    // Browsers set their own and send the page as Referer.
    if (_sendUserAgent) 'User-Agent': config.userAgent,
  };

  String get _language => AppStrings.isChinese ? 'zh-CN' : 'en';

  Uri _nominatimUri(String path, Map<String, String> query) {
    final base = Uri.parse(config.geocoderUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$basePath/$path',
      queryParameters: {
        ...base.queryParameters,
        ...query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'accept-language': _language,
      },
    );
  }

  Future<Object?> _getJson(Uri uri, RequestSpacer spacer) async {
    await spacer.turn();
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
    } on Object catch (error) {
      throw PlacesUnavailable('$error');
    }
    if (response.statusCode != 200) {
      throw PlacesUnavailable('HTTP ${response.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw PlacesUnavailable('$error');
    }
  }

  @override
  Future<List<PlaceInfo>> search(String query, {LatLng? near}) async {
    final text = query.trim();
    if (text.length < 2) {
      return const [];
    }
    final key = '$_language|${near == null ? '' : _cell(near, 2)}|$text';
    final cached = _searchCache[key];
    if (cached != null) {
      return cached;
    }
    final params = <String, String>{
      'q': text,
      'limit': '10',
      if (near != null)
        // Prefers (does not restrict to) what is around the person.
        'viewbox':
            '${near.longitude - 1},${near.latitude + 1},'
            '${near.longitude + 1},${near.latitude - 1}',
    };
    final json = await _getJson(_nominatimUri('search', params), _nominatim);
    final results = <PlaceInfo>[
      if (json is List)
        for (final item in json)
          if (item is Map<String, dynamic>)
            ?parseNominatimPlace(item, near: near),
    ];
    if (near != null) {
      results.sort(
        (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
          b.distanceMeters ?? double.infinity,
        ),
      );
    }
    _searchCache[key] = results;
    return results;
  }

  @override
  Future<PlaceInfo?> reverse(LatLng point) async {
    final key = _cell(point, 4);
    if (_reverseCache[key] case final cached?) {
      return cached;
    }
    final json = await _getJson(
      _nominatimUri('reverse', {
        'lat': point.latitude.toStringAsFixed(6),
        'lon': point.longitude.toStringAsFixed(6),
        'zoom': '18',
      }),
      _nominatim,
    );
    PlaceInfo? place;
    if (json is Map<String, dynamic> && json['error'] == null) {
      place = parseNominatimPlace(json)?.copyWith(point: point);
    }
    _reverseCache[key] = place;
    return place;
  }

  @override
  Future<List<PlaceInfo>> nearby(LatLng point) async {
    final key = _cell(point, 3);
    final cached = _nearbyCache[key];
    if (cached != null) {
      return cached;
    }
    await _overpass.turn();
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(config.placesUrl),
            headers: _headers,
            body: {'data': overpassNearbyQuery(point)},
          )
          .timeout(const Duration(seconds: 15));
    } on Object catch (error) {
      throw PlacesUnavailable('$error');
    }
    if (response.statusCode != 200) {
      throw PlacesUnavailable('HTTP ${response.statusCode}');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw PlacesUnavailable('$error');
    }
    final places = parseOverpassPlaces(
      json,
      around: point,
      chinese: AppStrings.isChinese,
    );
    _nearbyCache[key] = places;
    return places;
  }

  void close() => _client.close();
}

/// A cache key for the cell [point] is in, [decimals] places fine.
String _cell(LatLng point, int decimals) =>
    '${point.latitude.toStringAsFixed(decimals)},'
    '${point.longitude.toStringAsFixed(decimals)}';

/// The Overpass query for named places within [radius] meters of [point].
String overpassNearbyQuery(LatLng point, {int radius = 300}) {
  final around = '(around:$radius,${point.latitude},${point.longitude})';
  const keys = [
    '["amenity"]',
    '["shop"]',
    '["tourism"]',
    '["leisure"]',
    '["office"]',
    '["historic"]',
    '["railway"="station"]',
    '["public_transport"="station"]',
  ];
  return '[out:json][timeout:10];('
      '${[for (final key in keys) 'nwr$around["name"]$key;'].join()}'
      ');out center 60;';
}

/// Nominatim's place (a `search` or `reverse` result in jsonv2) as a
/// [PlaceInfo]; null when it has no usable position.
PlaceInfo? parseNominatimPlace(Map<String, dynamic> json, {LatLng? near}) {
  final lat = double.tryParse('${json['lat']}');
  final lon = double.tryParse('${json['lon']}');
  if (lat == null || lon == null || !isValidCoordinate(lat, lon)) {
    return null;
  }
  final point = LatLng(lat, lon);
  final address = json['address'] is Map
      ? Map<String, dynamic>.from(json['address'] as Map)
      : const <String, dynamic>{};
  String? str(Object? value) {
    final s = value is String ? value.trim() : '';
    return s.isEmpty ? null : s;
  }

  var name = str(json['name']);
  final street = _streetLine(address);
  final display = str(json['display_name']) ?? '';
  // A place without a name of its own is called by its street, which then
  // is not repeated in the address.
  final namedByStreet = name == null && street != null;
  var addressLine = _addressLine(
    address,
    exclude: name,
    withStreet: !namedByStreet,
  );
  if (addressLine.isEmpty && display.isNotEmpty) {
    final parts = display.split(',').map((p) => p.trim()).toList();
    if (name != null && parts.isNotEmpty && parts.first == name) {
      parts.removeAt(0);
    }
    addressLine = parts.take(4).join(', ');
  }
  name ??= street;
  return PlaceInfo(
    point: point,
    name: name ?? '',
    address: addressLine,
    distanceMeters: near == null ? null : distanceMeters(near, point),
  );
}

String? _streetLine(Map<String, dynamic> address) {
  final road = address['road'] ?? address['pedestrian'] ?? address['footway'];
  if (road is! String || road.trim().isEmpty) {
    return null;
  }
  final number = address['house_number'];
  return number is String && number.trim().isNotEmpty
      ? '${road.trim()} ${number.trim()}'
      : road.trim();
}

/// "Westminster, London, SW1A" from the parts Nominatim names.
String _addressLine(
  Map<String, dynamic> address, {
  String? exclude,
  bool withStreet = true,
}) {
  String? pick(List<String> keys) {
    for (final key in keys) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  final parts = <String>[
    if (withStreet) ?_streetLine(address),
    ?pick(['suburb', 'neighbourhood', 'quarter', 'city_district']),
    ?pick(['city', 'town', 'village', 'municipality', 'county']),
    ?pick(['state']),
    ?pick(['country']),
  ];
  final seen = <String>{};
  return [
    for (final part in parts)
      if (part != exclude && seen.add(part)) part,
  ].take(4).join(', ');
}

/// Overpass elements as places near [around], nearest first, without
/// duplicates.
List<PlaceInfo> parseOverpassPlaces(
  Object? json, {
  required LatLng around,
  bool chinese = false,
  int limit = 25,
}) {
  final elements = json is Map<String, dynamic> ? json['elements'] : null;
  if (elements is! List) {
    return const [];
  }
  final places = <PlaceInfo>[];
  final seen = <String>{};
  for (final element in elements) {
    if (element is! Map<String, dynamic>) {
      continue;
    }
    final center = element['center'];
    final lat = (element['lat'] ?? (center is Map ? center['lat'] : null));
    final lon = (element['lon'] ?? (center is Map ? center['lon'] : null));
    final tags = element['tags'];
    if (lat is! num || lon is! num || tags is! Map) {
      continue;
    }
    String? tag(String key) {
      final value = tags[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final name =
        (chinese ? tag('name:zh') : tag('name:en')) ??
        tag('name') ??
        tag('name:en');
    if (name == null || !isValidCoordinate(lat, lon)) {
      continue;
    }
    final point = LatLng(lat.toDouble(), lon.toDouble());
    final street = tag('addr:street');
    final number = tag('addr:housenumber');
    final city = tag('addr:city');
    final addressParts = <String>[
      if (street != null) number == null ? street : '$street $number',
      ?city,
    ];
    final kind =
        tag('amenity') ??
        tag('shop') ??
        tag('tourism') ??
        tag('leisure') ??
        tag('historic') ??
        tag('office') ??
        tag('railway') ??
        tag('public_transport');
    final address = addressParts.isNotEmpty
        ? addressParts.join(', ')
        : _titleCase(kind) ?? '';
    final key = '${name.toLowerCase()}|${point.latitude.toStringAsFixed(3)}';
    if (!seen.add(key)) {
      continue;
    }
    places.add(
      PlaceInfo(
        point: point,
        name: name,
        address: address,
        distanceMeters: distanceMeters(around, point),
      ),
    );
  }
  places.sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
  return places.take(limit).toList();
}

String? _titleCase(String? raw) {
  if (raw == null || raw == 'yes') {
    return null;
  }
  final words = raw.replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

final placesServiceProvider = Provider<PlacesService>((ref) {
  final service = NominatimPlacesService(config: ref.watch(mapConfigProvider));
  ref.onDispose(service.close);
  return service;
});
