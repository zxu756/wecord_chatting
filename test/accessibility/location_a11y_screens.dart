// The location screens (the picker, a shared place, the consent sheet and the
// live map), for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool. They run on fake map tiles.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/live_location_map_screen.dart';
import 'package:wecord/features/location/live_location_start_sheet.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_picker_screen.dart';
import 'package:wecord/features/location/location_viewer_screen.dart';

import '../features/location/location_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

LocationWorld _world() {
  final world = LocationWorld();
  world.places
    ..reverseResult = const PlaceInfo(
      point: westminster,
      name: 'Bridge Street',
      address: 'Westminster, London',
    )
    ..nearbyPlaces = const [
      PlaceInfo(
        point: LatLng(51.5009, -0.1244),
        name: 'Café Nero',
        address: 'Cafe',
        distanceMeters: 30,
      ),
      PlaceInfo(
        point: LatLng(51.5011, -0.1246),
        name: 'The Red Lion',
        address: 'Parliament Street 48',
        distanceMeters: 55,
      ),
    ];
  return world;
}

Future<void> _show(
  WidgetTester tester,
  PhoneWorld world,
  LocationWorld location,
  Widget screen,
) async {
  await pumpStandalone(
    tester,
    world,
    screen,
    extraOverrides: location.overrides,
  );
  await settleMaps(tester);
}

final locationA11yScreens = <A11yScreen>[
  A11yScreen('location-picker', (tester, world) async {
    await _show(tester, world, _world(), const LocationPickerScreen());
  }),
  A11yScreen('location-viewer', (tester, world) async {
    await _show(
      tester,
      world,
      _world(),
      const LocationViewerScreen(
        place: PlaceInfo(
          point: LatLng(51.5007, -0.1246),
          name: 'Big Ben',
          address: 'Westminster, London',
        ),
        sharedBy: 'Ada',
      ),
    );
  }),
  A11yScreen('location-consent', (tester, world) async {
    await _show(
      tester,
      world,
      _world(),
      const Scaffold(body: LiveLocationConsentSheet()),
    );
  }),
  A11yScreen('live-location-map', (tester, world) async {
    final location = _world();
    location.repository
      ..addShare(otherShare('s-bart', 'user-2', 'Bart'))
      ..addShare(
        otherShare(
          's-grace',
          'user-3',
          'Grace',
          left: const Duration(hours: 3),
        ),
      );
    await _show(
      tester,
      world,
      location,
      const LiveLocationMapScreen(conversationId: 'dm-1'),
    );
    location.repository
        .channel('s-bart')
        .receive(
          LivePosition(
            point: const LatLng(51.5012, -0.1229),
            at: DateTime.now().toUtc(),
          ),
        );
    await settleMaps(tester);
  }),
];
