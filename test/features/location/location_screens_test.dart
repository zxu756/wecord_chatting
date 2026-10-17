import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_picker_screen.dart';
import 'package:wecord/features/location/location_service.dart';
import 'package:wecord/features/location/location_viewer_screen.dart';
import 'package:wecord/features/location/open_in_maps.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';
import 'location_fakes.dart';

/// A page with a button that opens [open] and keeps what it returns.
class _Host extends ConsumerWidget {
  const _Host({required this.open, required this.onResult});

  final Future<Object?> Function(BuildContext context) open;
  final ValueChanged<Object?> onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('open'),
          onPressed: () async => onResult(await open(context)),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  LocationWorld world,
  Future<Object?> Function(BuildContext context) open, {
  required ValueChanged<Object?> onResult,
  ThemeData? theme,
  TargetPlatform? platform,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: world.overrides,
      child: MaterialApp(
        theme: (theme ?? WeCordTheme.light()).copyWith(platform: platform),
        home: _Host(open: open, onResult: onResult),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await settleMaps(tester);
}

const _bigBen = PlaceInfo(
  point: LatLng(51.5007, -0.1246),
  name: 'Big Ben',
  address: 'Westminster, London',
);

LocationWorld _worldWithPlaces() {
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

void main() {
  setUp(() => AppStrings.isChinese = false);

  group('the picker', () {
    testWidgets('opens on where the person is and lists what is there', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      await _pump(tester, world, showLocationPicker, onResult: (_) {});

      expect(find.text('Send location'), findsOneWidget);
      expect(find.byKey(const ValueKey('location-picker-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('location-center-pin')), findsOneWidget);
      // The pin is at the person, so that is what the first row says.
      expect(find.text('Current location'), findsOneWidget);
      expect(find.text('Westminster, London'), findsOneWidget);
      expect(find.text('Nearby places'), findsOneWidget);
      expect(find.text('Café Nero'), findsOneWidget);
      expect(find.textContaining('30 m'), findsOneWidget);
      expect(find.text('The Red Lion'), findsOneWidget);
      expect(world.places.reversed.last.latitude, closeTo(51.5007, 1e-4));
      // The credit stays on the map.
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });

    testWidgets('sending the pin sends where the person is, with its name', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      Object? result;
      await _pump(
        tester,
        world,
        showLocationPicker,
        onResult: (value) => result = value,
      );

      await tester.tap(find.byKey(const ValueKey('location-send')));
      await settleMaps(tester);

      final place = result as PlaceInfo;
      expect(place.point.latitude, closeTo(51.5007, 1e-3));
      expect(place.name, 'Bridge Street');
      expect(place.address, 'Westminster, London');
      expect(find.text('Send location'), findsNothing);
    });

    testWidgets('choosing a nearby place sends that place', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      Object? result;
      await _pump(
        tester,
        world,
        showLocationPicker,
        onResult: (value) => result = value,
      );

      await tester.tap(find.text('Café Nero'));
      await settleMaps(tester);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('location-send')));
      await settleMaps(tester);
      final place = result as PlaceInfo;
      expect(place.name, 'Café Nero');
      expect(place.point, const LatLng(51.5009, -0.1244));
    });

    testWidgets('dragging the map moves the pin and names the new spot', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      Object? result;
      await _pump(
        tester,
        world,
        showLocationPicker,
        onResult: (value) => result = value,
      );
      final before = world.places.reversed.length;
      world.places.reverseResult = const PlaceInfo(
        point: LatLng(51.51, -0.13),
        name: 'Trafalgar Square',
        address: 'Charing Cross, London',
      );

      await tester.drag(
        find.byKey(const ValueKey('location-picker-map')),
        const Offset(-120, -90),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Dragged: nothing is chosen from the list any more.
      await tester.pump(const Duration(milliseconds: 800));
      await settleMaps(tester);

      expect(world.places.reversed.length, greaterThan(before));
      expect(find.text('Trafalgar Square'), findsOneWidget);
      expect(find.text('Current location'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('location-send')));
      await settleMaps(tester);
      final place = result as PlaceInfo;
      expect(place.name, 'Trafalgar Square');
      // The pin moved with the map, to the south-east of where it was.
      expect(place.point.latitude, lessThan(51.5007));
      expect(place.point.longitude, greaterThan(-0.1246));
    });

    testWidgets('an unnamed spot is a dropped pin with its address', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      world.places.reverseResult = const PlaceInfo(
        point: westminster,
        address: 'Elm Street, Springfield',
      );
      Object? result;
      await _pump(
        tester,
        world,
        showLocationPicker,
        onResult: (value) => result = value,
      );
      await tester.drag(
        find.byKey(const ValueKey('location-picker-map')),
        const Offset(200, 100),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await settleMaps(tester);
      expect(find.text('Dropped pin'), findsOneWidget);
      expect(find.text('Elm Street, Springfield'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('location-send')));
      await settleMaps(tester);
      expect((result as PlaceInfo).name, 'Dropped pin');
    });

    testWidgets('search lists places, and choosing one sends it', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      world.places.searchResults['big ben'] = const [_bigBen];
      Object? result;
      await _pump(
        tester,
        world,
        showLocationPicker,
        onResult: (value) => result = value,
      );

      await tester.enterText(
        find.byKey(const ValueKey('location-search-field')),
        'big ben',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await settleMaps(tester);
      expect(world.places.searches, ['big ben']);
      expect(find.text('Big Ben'), findsOneWidget);
      // While searching, the nearby list gives way to the results.
      expect(find.text('Café Nero'), findsNothing);

      await tester.tap(find.text('Big Ben'));
      await settleMaps(tester);
      // Back to the list, with the result chosen.
      expect(find.text('Café Nero'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('location-send')));
      await settleMaps(tester);
      expect(result, _bigBen);
    });

    testWidgets('a search that fails or finds nothing says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      await _pump(tester, world, showLocationPicker, onResult: (_) {});

      await tester.enterText(
        find.byKey(const ValueKey('location-search-field')),
        'zzzz',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await settleMaps(tester);
      expect(find.text('No places found.'), findsOneWidget);

      world.places.failSearch = const PlacesUnavailableForTest();
      await tester.enterText(
        find.byKey(const ValueKey('location-search-field')),
        'yyyy',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await settleMaps(tester);
      expect(find.textContaining("Couldn't search right now"), findsOneWidget);
    });

    testWidgets('nearby places that do not load still leave the pin to send', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces()
        ..places.failNearby = const PlacesUnavailableForTest();
      await _pump(tester, world, showLocationPicker, onResult: (_) {});
      expect(
        find.textContaining("Couldn't load nearby places"),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('location-send')), findsOneWidget);
    });

    testWidgets('asks for permission first, and still works without it', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      world.service
        ..current = LocationAccess.denied
        ..answerWhenAsked = LocationAccess.denied;
      Object? result;
      await _pump(
        tester,
        world,
        showLocationPicker,
        onResult: (value) => result = value,
      );

      expect(world.service.requests, 1);
      expect(
        find.text('Allow location to start from where you are.'),
        findsOneWidget,
      );
      // Nothing centres on the person, but the map can still be used.
      expect(find.text('Current location'), findsNothing);

      // Allowing it later centres the map.
      world.service.answerWhenAsked = LocationAccess.granted;
      await tester.tap(find.byKey(const ValueKey('location-allow')));
      await settleMaps(tester);
      expect(world.service.requests, 2);
      expect(find.text('Current location'), findsOneWidget);
      expect(find.byKey(const ValueKey('location-allow')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('location-picker-close')));
      await settleMaps(tester);
      expect(result, isNull);
    });

    testWidgets('refused for good points to the settings', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      world.service.current = LocationAccess.deniedForever;
      await _pump(tester, world, showLocationPicker, onResult: (_) {});

      expect(world.service.requests, 0);
      expect(find.textContaining('Location is off for WeCord'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('location-allow')));
      await settleMaps(tester);
      expect(world.service.settingsOpened, 1);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('location services off says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = _worldWithPlaces();
      world.service.current = LocationAccess.serviceOff;
      await _pump(tester, world, showLocationPicker, onResult: (_) {});
      expect(find.textContaining('Location services are off'), findsOneWidget);
    });

    testWidgets('on a wide screen the list sits beside the map in a window', (
      tester,
    ) async {
      usePhoneViewport(tester, desktopViewportForTest);
      final world = _worldWithPlaces();
      await _pump(tester, world, showLocationPicker, onResult: (_) {});

      final panel = tester.getRect(find.text('Send location'));
      final map = tester.getRect(
        find.byKey(const ValueKey('location-picker-map')),
      );
      expect(panel.right, lessThan(map.left));
      expect(find.text('Café Nero'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('location-my-location')),
        findsOneWidget,
      );
    });
  });

  group('a shared place', () {
    testWidgets('shows the pin, the name and the address', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = LocationWorld();
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(context, _bigBen, sharedBy: 'Ada'),
        onResult: (_) {},
      );
      expect(find.byKey(const ValueKey('location-viewer-map')), findsOneWidget);
      expect(find.text('Big Ben'), findsOneWidget);
      expect(find.text('Westminster, London'), findsOneWidget);
      expect(find.text('Shared by Ada'), findsOneWidget);
      // The (fake) tiles were drawn.
      expect(find.byType(RawImage), findsWidgets);
    });

    testWidgets('Open in Maps opens Apple Maps on iOS and macOS', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = LocationWorld();
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(context, _bigBen),
        onResult: (_) {},
        platform: TargetPlatform.iOS,
      );
      await tester.tap(find.byKey(const ValueKey('location-open-in-maps')));
      await settleMaps(tester);
      expect(world.launcher.opened.single.host, 'maps.apple.com');
      expect(
        world.launcher.opened.single.queryParameters['ll'],
        '51.500700,-0.124600',
      );
    });

    testWidgets('in a browser it offers Google Maps and OpenStreetMap', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = LocationWorld(isWeb: true);
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(context, _bigBen),
        onResult: (_) {},
      );
      await tester.tap(find.byKey(const ValueKey('location-open-in-maps')));
      await settleMaps(tester);
      expect(find.text('Open in Google Maps'), findsOneWidget);
      expect(find.text('Open in OpenStreetMap'), findsOneWidget);
      expect(world.launcher.opened, isEmpty);

      await tester.tap(find.text('Open in OpenStreetMap'));
      await settleMaps(tester);
      expect(world.launcher.opened.single.host, 'www.openstreetmap.org');
    });

    testWidgets('a map that will not open says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = LocationWorld();
      world.launcher.succeeds = false;
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(context, _bigBen),
        onResult: (_) {},
        platform: TargetPlatform.iOS,
      );
      await tester.tap(find.byKey(const ValueKey('location-open-in-maps')));
      await settleMaps(tester);
      expect(find.text('Could not open the map.'), findsOneWidget);
    });

    testWidgets('Copy address puts the name and address on the clipboard', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = LocationWorld();
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(context, _bigBen),
        onResult: (_) {},
      );
      await tester.tap(find.byKey(const ValueKey('location-copy-address')));
      await settleMaps(tester);
      expect(world.launcher.copied, ['Big Ben, Westminster, London']);
      expect(find.text('Address copied'), findsOneWidget);
    });

    testWidgets('a bare pin shows its address as the title', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = LocationWorld();
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(
          context,
          const PlaceInfo(point: LatLng(1, 2), address: 'Elm Street'),
        ),
        onResult: (_) {},
      );
      expect(
        find.byKey(const ValueKey('location-viewer-title')),
        findsOneWidget,
      );
      expect(find.text('Elm Street'), findsOneWidget);
    });

    testWidgets('Back closes it', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = LocationWorld();
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(context, _bigBen),
        onResult: (_) {},
      );
      await tester.tap(find.byKey(const ValueKey('location-viewer-close')));
      await settleMaps(tester);
      expect(find.byKey(const ValueKey('location-viewer-map')), findsNothing);
    });

    testWidgets('on a wide screen it opens in a window with zoom buttons', (
      tester,
    ) async {
      usePhoneViewport(tester, desktopViewportForTest);
      final world = LocationWorld();
      await _pump(
        tester,
        world,
        (context) => showLocationViewer(context, _bigBen),
        onResult: (_) {},
        platform: TargetPlatform.macOS,
      );
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      final map = tester.getRect(
        find.byKey(const ValueKey('location-viewer-map')),
      );
      expect(map.width, lessThan(1100));
      await tester.tap(find.byTooltip('Zoom in'));
      await settleMaps(tester);
      expect(find.text('Big Ben'), findsOneWidget);
    });
  });

  testWidgets('the clipboard really gets the text', (tester) async {
    // The default launcher writes to the system clipboard.
    String? written;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          written = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await const SystemMapsLauncher().copy('Big Ben, Westminster');
    expect(written, 'Big Ben, Westminster');
  });
}

const desktopViewportForTest = PhoneViewport(
  name: '1280x800',
  size: Size(1280, 800),
  devicePixelRatio: 1,
);

/// Stands in for the server being down.
class PlacesUnavailableForTest implements Exception {
  const PlacesUnavailableForTest();
}
