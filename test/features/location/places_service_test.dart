import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/map_config.dart';
import 'package:wecord/features/location/places_service.dart';
import 'package:wecord/shared/l10n/l10n.dart';

const _here = LatLng(51.5007, -0.1246);

Map<String, dynamic> _bigBen() => {
  'lat': '51.5007',
  'lon': '-0.1246',
  'name': 'Big Ben',
  'category': 'tourism',
  'display_name': 'Big Ben, Westminster, London, England, United Kingdom',
  'address': {
    'tourism': 'Big Ben',
    'road': 'Bridge Street',
    'suburb': 'Westminster',
    'city': 'London',
    'state': 'England',
    'country': 'United Kingdom',
  },
};

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

NominatimPlacesService _service(
  MockClient client, {
  MapConfig config = const MapConfig(),
  bool sendUserAgent = true,
}) {
  return NominatimPlacesService(
    config: config,
    client: client,
    nominatimSpacer: RequestSpacer(gap: Duration.zero),
    overpassSpacer: RequestSpacer(gap: Duration.zero),
    sendUserAgent: sendUserAgent,
  );
}

void main() {
  setUp(() => AppStrings.isChinese = false);

  group('Nominatim places', () {
    test('a result has the name, a short address and the distance', () {
      final place = parseNominatimPlace(_bigBen(), near: _here)!;
      expect(place.name, 'Big Ben');
      expect(place.address, 'Bridge Street, Westminster, London, England');
      expect(place.point, const LatLng(51.5007, -0.1246));
      expect(place.distanceMeters, closeTo(0, 1));
    });

    test('a street with no place name is named after the street', () {
      final place = parseNominatimPlace({
        'lat': '51.5',
        'lon': '-0.12',
        'name': '',
        'display_name': '10, Whitehall, Westminster, London',
        'address': {
          'house_number': '10',
          'road': 'Whitehall',
          'city': 'London',
        },
      })!;
      expect(place.name, 'Whitehall 10');
      expect(place.address, 'London');
    });

    test('without address parts the display name is used', () {
      final place = parseNominatimPlace({
        'lat': '1',
        'lon': '2',
        'name': 'Somewhere',
        'display_name': 'Somewhere, A, B, C, D, E',
      })!;
      expect(place.address, 'A, B, C, D');
    });

    test('a result without a usable position is skipped', () {
      expect(parseNominatimPlace({'lat': 'x', 'lon': '1'}), isNull);
      expect(parseNominatimPlace({'lat': '95', 'lon': '1'}), isNull);
    });

    test(
      'search asks for the query, our language and an identifying agent',
      () async {
        late http.Request seen;
        final service = _service(
          MockClient((request) async {
            seen = request;
            return _json([_bigBen()]);
          }),
        );
        final results = await service.search('big ben', near: _here);
        expect(results.single.name, 'Big Ben');
        expect(seen.url.host, 'nominatim.openstreetmap.org');
        expect(seen.url.path, '/search');
        expect(seen.url.queryParameters['q'], 'big ben');
        expect(seen.url.queryParameters['format'], 'jsonv2');
        expect(seen.url.queryParameters['accept-language'], 'en');
        expect(seen.url.queryParameters['viewbox'], isNotEmpty);
        expect(seen.headers['User-Agent'], MapConfig.defaultUserAgent);
      },
    );

    test('in a browser no User-Agent is set (it cannot be)', () async {
      late http.Request seen;
      final service = _service(
        MockClient((request) async {
          seen = request;
          return _json([]);
        }),
        sendUserAgent: false,
      );
      await service.search('big ben');
      expect(seen.headers.containsKey('User-Agent'), isFalse);
    });

    test('the server is configurable, with a path', () async {
      late http.Request seen;
      final service = _service(
        MockClient((request) async {
          seen = request;
          return _json([]);
        }),
        config: const MapConfig(
          geocoderUrl: 'https://geo.example.com/nominatim/',
        ),
      );
      await service.search('cafe');
      expect(
        seen.url.toString(),
        startsWith('https://geo.example.com/nominatim/search?'),
      );
    });

    test('Chinese asks for Chinese names', () async {
      AppStrings.isChinese = true;
      late http.Request seen;
      final service = _service(
        MockClient((request) async {
          seen = request;
          return _json([]);
        }),
      );
      await service.search('天安门');
      expect(seen.url.queryParameters['accept-language'], 'zh-CN');
    });

    test('short queries do not reach the server', () async {
      var calls = 0;
      final service = _service(
        MockClient((request) async {
          calls += 1;
          return _json([]);
        }),
      );
      expect(await service.search(' a '), isEmpty);
      expect(calls, 0);
    });

    test('results are closest first and repeats come from the cache', () async {
      var calls = 0;
      final far = _bigBen()
        ..['lat'] = '52.0'
        ..['name'] = 'Far';
      final service = _service(
        MockClient((request) async {
          calls += 1;
          return _json([far, _bigBen()]);
        }),
      );
      final first = await service.search('big', near: _here);
      expect(first.map((p) => p.name), ['Big Ben', 'Far']);
      await service.search('big', near: _here);
      expect(calls, 1);
    });

    test('a refusing server is reported, not hidden', () async {
      final service = _service(MockClient((request) async => _json({}, 429)));
      await expectLater(
        service.search('big ben'),
        throwsA(isA<PlacesUnavailable>()),
      );
    });

    test('a dead network is reported', () async {
      final service = _service(
        MockClient((request) async => throw http.ClientException('offline')),
      );
      await expectLater(
        service.reverse(_here),
        throwsA(isA<PlacesUnavailable>()),
      );
    });

    test('reverse names the spot and is cached by cell', () async {
      var calls = 0;
      final service = _service(
        MockClient((request) async {
          calls += 1;
          expect(request.url.path, '/reverse');
          expect(request.url.queryParameters['lat'], '51.500700');
          return _json(_bigBen());
        }),
      );
      final place = await service.reverse(_here);
      expect(place!.name, 'Big Ben');
      // The place is where the pin is, not where the server put it.
      expect(place.point, _here);
      await service.reverse(const LatLng(51.50071, -0.12461));
      expect(calls, 1);
    });

    test('nothing there is null', () async {
      final service = _service(
        MockClient((request) async => _json({'error': 'Unable to geocode'})),
      );
      expect(await service.reverse(_here), isNull);
    });
  });

  group('requests are one a second', () {
    test('the spacer queues callers 1.1 s apart', () {
      fakeAsync((async) {
        final spacer = RequestSpacer();
        final times = <int>[];
        final start = async.elapsed;
        for (var i = 0; i < 3; i++) {
          spacer.turn().then(
            (_) => times.add((async.elapsed - start).inMilliseconds),
          );
        }
        async.flushMicrotasks();
        expect(times, [0]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(times, [0, 1100]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(times, [0, 1100, 2200]);
      });
    });

    test('a quiet minute resets the queue', () {
      fakeAsync((async) {
        final spacer = RequestSpacer();
        var turns = 0;
        spacer.turn().then((_) => turns++);
        async.elapse(const Duration(minutes: 1));
        spacer.turn().then((_) => turns++);
        async.flushMicrotasks();
        expect(turns, 2);
      });
    });
  });

  group('Overpass nearby places', () {
    final response = {
      'elements': [
        {
          'type': 'node',
          'lat': 51.5011,
          'lon': -0.1246,
          'tags': {
            'name': 'The Red Lion',
            'amenity': 'pub',
            'addr:street': 'Parliament Street',
            'addr:housenumber': '48',
          },
        },
        {
          'type': 'way',
          'center': {'lat': 51.5009, 'lon': -0.1244},
          'tags': {'name': 'Café Nero', 'name:zh': '星巴克', 'amenity': 'cafe'},
        },
        {
          'type': 'node',
          'lat': 51.5012,
          'lon': -0.1247,
          'tags': {'amenity': 'bench'},
        },
        {
          'type': 'node',
          'lat': 51.5011,
          'lon': -0.1246,
          'tags': {'name': 'The Red Lion', 'amenity': 'pub'},
        },
      ],
    };

    test('named places only, nearest first, no repeats', () {
      final places = parseOverpassPlaces(response, around: _here);
      expect(places.map((p) => p.name), ['Café Nero', 'The Red Lion']);
      expect(places.first.address, 'Cafe');
      expect(places.last.address, 'Parliament Street 48');
      expect(
        places.first.distanceMeters,
        lessThan(places.last.distanceMeters!),
      );
    });

    test('Chinese prefers the Chinese name', () {
      final places = parseOverpassPlaces(
        response,
        around: _here,
        chinese: true,
      );
      expect(places.first.name, '星巴克');
    });

    test('garbage gives nothing', () {
      expect(parseOverpassPlaces(null, around: _here), isEmpty);
      expect(parseOverpassPlaces({'elements': 3}, around: _here), isEmpty);
    });

    test('the query looks around the point', () {
      final query = overpassNearbyQuery(_here, radius: 250);
      expect(query, contains('(around:250,51.5007,-0.1246)'));
      expect(query, contains('["name"]["amenity"]'));
      expect(query, contains('out center'));
    });

    test('nearby posts the query to the configured endpoint', () async {
      late http.Request seen;
      final service = _service(
        MockClient((request) async {
          seen = request;
          return _json(response);
        }),
        config: const MapConfig(
          placesUrl: 'https://overpass.example.com/api/interpreter',
        ),
      );
      final places = await service.nearby(_here);
      expect(places, hasLength(2));
      expect(seen.method, 'POST');
      expect(seen.url.host, 'overpass.example.com');
      expect(seen.body, contains('data='));
      expect(seen.headers['User-Agent'], MapConfig.defaultUserAgent);
    });

    test('a busy Overpass is reported', () async {
      final service = _service(MockClient((request) async => _json({}, 504)));
      await expectLater(
        service.nearby(_here),
        throwsA(isA<PlacesUnavailable>()),
      );
    });
  });

  group('map configuration', () {
    test('the defaults are OpenStreetMap with its credit', () {
      const config = MapConfig();
      expect(config.tileUrl, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(config.attribution, contains('OpenStreetMap'));
      expect(config.attributionUrl, 'https://www.openstreetmap.org/copyright');
      expect(config.usesPublicOsmTiles, isTrue);
      expect(config.userAgent, contains('WeCord'));
    });

    test('a provider with a key is not the public server', () {
      const config = MapConfig(
        tileUrl:
            'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=k',
        attribution: '© MapTiler © OpenStreetMap contributors',
      );
      expect(config.usesPublicOsmTiles, isFalse);
    });

    test('without --dart-define the environment gives the defaults', () {
      final config = MapConfig.fromEnvironment();
      expect(config.tileUrl, MapConfig.defaultTileUrl);
      expect(config.geocoderUrl, MapConfig.defaultGeocoderUrl);
      expect(config.placesUrl, MapConfig.defaultPlacesUrl);
    });
  });
}
