import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/location_format.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/open_in_maps.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:flutter/foundation.dart';

ChatMessage _message(Map<String, dynamic>? attachment, {String? recalledAt}) {
  return ChatMessage.fromJson({
    'id': 'm1',
    'conversation_id': 'c1',
    'sender_id': 'u1',
    'type': 'text',
    'body': '📍 Big Ben · Westminster',
    'attachment': attachment,
    'created_at': '2026-10-18T12:00:00Z',
    'recalled_at': recalledAt,
  });
}

void main() {
  group('location cards', () {
    test('a location message carries its place', () {
      final card = _message({
        'kind': 'location',
        'lat': 51.5007,
        'lng': -0.1246,
        'name': 'Big Ben',
        'address': 'Westminster, London',
      }).locationCard;
      expect(card, isNotNull);
      expect(card!.point, const LatLng(51.5007, -0.1246));
      expect(card.name, 'Big Ben');
      expect(card.address, 'Westminster, London');
      expect(card.place.hasName, isTrue);
    });

    test('a pin without a name or address is still a place', () {
      final card = _message({
        'kind': 'location',
        'lat': 10,
        'lng': 20,
        'name': '',
        'address': '',
      }).locationCard;
      expect(card, isNotNull);
      expect(card!.place.hasName, isFalse);
      expect(card.place.hasAddress, isFalse);
    });

    test('damaged cards are ignored, not shown', () {
      for (final attachment in <Map<String, dynamic>?>[
        null,
        {'kind': 'location'},
        {'kind': 'location', 'lat': 'x', 'lng': 1},
        {'kind': 'location', 'lat': 91, 'lng': 0},
        {'kind': 'location', 'lat': 0, 'lng': 181},
        {'kind': 'location', 'lat': double.nan, 'lng': 0},
        {'kind': 'note', 'note_id': 'n'},
      ]) {
        expect(
          _message(attachment).locationCard,
          isNull,
          reason: '$attachment',
        );
      }
    });

    test('long names are cut so a card cannot fill the screen', () {
      final card = _message({
        'kind': 'location',
        'lat': 1,
        'lng': 2,
        'name': 'N' * 500,
        'address': 'A' * 900,
      }).locationCard!;
      expect(card.name.length, 200);
      expect(card.address.length, 400);
    });

    test('a deleted location message shows no card', () {
      final message = _message({
        'kind': 'location',
        'lat': 1,
        'lng': 2,
      }, recalledAt: '2026-10-18T12:05:00Z');
      expect(message.locationCard, isNull);
    });

    test('a live location card names its share and end', () {
      final card = _message({
        'kind': 'live_location',
        'share_id': 'share-1',
        'ends_at': '2026-10-18T13:00:00+00:00',
        'precise': true,
      }).liveLocationCard;
      expect(card, isNotNull);
      expect(card!.shareId, 'share-1');
      expect(card.endsAt, DateTime.utc(2026, 10, 18, 13));
      expect(card.precise, isTrue);
      expect(_message({'kind': 'live_location'}).liveLocationCard, isNull);
      expect(
        _message({
          'kind': 'live_location',
          'share_id': 's',
          'ends_at': 'soon',
        }).liveLocationCard,
        isNull,
      );
    });
  });

  group('positions', () {
    test('a position survives the trip', () {
      final position = LivePosition(
        point: const LatLng(51.5, -0.12),
        at: DateTime.utc(2026, 10, 18, 12, 30),
        accuracyMeters: 8,
        heading: 90,
      );
      final back = LivePosition.maybeFromPayload(position.toPayload())!;
      expect(back.point, position.point);
      expect(back.at, position.at);
      expect(back.accuracyMeters, 8);
      expect(back.heading, 90);
    });

    test('nonsense payloads are dropped', () {
      expect(LivePosition.maybeFromPayload(null), isNull);
      expect(LivePosition.maybeFromPayload({'lat': 'a', 'lng': 1}), isNull);
      expect(LivePosition.maybeFromPayload({'lat': 200, 'lng': 1}), isNull);
      expect(LivePosition.maybeFromPayload({'lat': 1}), isNull);
    });

    test('a coarse position is snapped to a grid of about 500 m', () {
      final coarse = coarsen(const LatLng(51.50073, -0.12462));
      expect(coarse.latitude, closeTo(51.5, 1e-9));
      expect(coarse.longitude, closeTo(-0.125, 1e-9));
      // Two readings a few meters apart become the same point.
      expect(
        coarsen(const LatLng(51.50073, -0.12462)),
        coarsen(const LatLng(51.50081, -0.12459)),
      );
      // And never move more than the grid allows.
      expect(
        distanceMeters(const LatLng(51.50073, -0.12462), coarse),
        lessThan(500),
      );
    });

    test('coarsening keeps the poles and the date line on the globe', () {
      final p = coarsen(const LatLng(89.999, 179.999));
      expect(p.latitude, lessThanOrEqualTo(90));
      expect(p.longitude, lessThanOrEqualTo(180));
    });
  });

  group('distance', () {
    test('Big Ben to the London Eye is about 700 m', () {
      final meters = distanceMeters(
        const LatLng(51.5007, -0.1246),
        const LatLng(51.5033, -0.1196),
      );
      expect(meters, inInclusiveRange(400, 600));
    });

    test('it reads as meters then kilometers', () {
      expect(formatDistance(3), '5 m');
      expect(formatDistance(42), '40 m');
      expect(formatDistance(180), '180 m');
      expect(formatDistance(1234), '1.2 km');
      expect(formatDistance(25000), '25 km');
    });
  });

  group('open in maps', () {
    const place = PlaceInfo(
      point: LatLng(51.5007, -0.1246),
      name: 'Big Ben',
      address: 'Westminster, London',
    );

    test(
      'Apple Maps on iOS and macOS, Google and OpenStreetMap on the web',
      () {
        expect(mapsAppsFor(isWeb: false, platform: TargetPlatform.iOS), [
          MapsApp.apple,
        ]);
        expect(mapsAppsFor(isWeb: false, platform: TargetPlatform.macOS), [
          MapsApp.apple,
        ]);
        expect(mapsAppsFor(isWeb: true, platform: TargetPlatform.macOS), [
          MapsApp.google,
          MapsApp.openStreetMap,
        ]);
        expect(mapsAppsFor(isWeb: true, platform: TargetPlatform.iOS), [
          MapsApp.google,
          MapsApp.openStreetMap,
        ]);
      },
    );

    test('links pin the place', () {
      final apple = mapsUri(MapsApp.apple, place);
      expect(apple.host, 'maps.apple.com');
      expect(apple.queryParameters['ll'], '51.500700,-0.124600');
      expect(apple.queryParameters['q'], 'Big Ben');

      final google = mapsUri(MapsApp.google, place);
      expect(google.host, 'www.google.com');
      expect(google.queryParameters['query'], '51.500700,-0.124600');

      final osm = mapsUri(MapsApp.openStreetMap, place);
      expect(osm.host, 'www.openstreetmap.org');
      expect(osm.queryParameters['mlat'], '51.500700');
      expect(osm.fragment, 'map=17/51.500700/-0.124600');
    });

    test('an unnamed pin has no name in the Apple link', () {
      final apple = mapsUri(
        MapsApp.apple,
        const PlaceInfo(point: LatLng(1, 2)),
      );
      expect(apple.queryParameters.containsKey('q'), isFalse);
    });

    test('copy address: name and address, or the coordinates', () {
      expect(copyableAddress(place), 'Big Ben, Westminster, London');
      expect(
        copyableAddress(
          const PlaceInfo(point: LatLng(1, 2), address: 'Elm St'),
        ),
        'Elm St',
      );
      expect(
        copyableAddress(const PlaceInfo(point: LatLng(1.5, 2.25))),
        '1.50000, 2.25000',
      );
    });
  });

  group('time words', () {
    setUp(() => AppStrings.isChinese = false);

    test('time left', () {
      expect(timeLeftLabel(Duration.zero), 'Ended');
      expect(
        timeLeftLabel(const Duration(seconds: 30)),
        'Less than a minute left',
      );
      expect(
        timeLeftLabel(const Duration(minutes: 42, seconds: 10)),
        '42 min left',
      );
      expect(
        timeLeftLabel(const Duration(hours: 1, minutes: 5)),
        '1 h 5 min left',
      );
      expect(timeLeftLabel(const Duration(hours: 8)), '8 h left');
    });

    test('how old a position is', () {
      expect(agoLabel(const Duration(seconds: 3)), 'Just now');
      expect(agoLabel(const Duration(seconds: 30)), '30 s ago');
      expect(agoLabel(const Duration(minutes: 3)), '3m ago');
      expect(agoLabel(const Duration(hours: 2)), '2h ago');
    });
  });
}
