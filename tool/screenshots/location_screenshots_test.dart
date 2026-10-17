// Renders sending a location and sharing it live (the + menu, the picker, a
// shared place, location cards and the live banner in a chat, the consent
// sheet and the live map) on a phone and a desktop, light and dark, with real
// fonts and fake map tiles (no network), and writes PNGs for eyeballing. Not
// part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/location_screenshots_test.dart \
//     --dart-define=LOCATION_SCREENS_DIR=build/location
//
// Pick screens with --dart-define=LOCATION_ONLY=chat,menu,picker,search,
// denied,viewer,consent,live.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_service.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/location/location_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'LOCATION_SCREENS_DIR',
  defaultValue: 'build/location',
);
const _only = String.fromEnvironment('LOCATION_ONLY');

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

class _Variant {
  const _Variant(this.name, this.viewport, this.dark);

  final String name;
  final PhoneViewport viewport;
  final bool dark;

  bool get desktop => viewport == _desktop;
}

const _variants = [
  _Variant('phone-light', notchedPhone, false),
  _Variant('phone-dark', notchedPhone, true),
  _Variant('desktop-light', _desktop, false),
  _Variant('desktop-dark', _desktop, true),
];

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settleMaps(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  final only = _only.isEmpty ? null : _only.split(',').toSet();

  void screen(
    String group,
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      LocationWorld location,
      _Variant variant,
    )
    open,
  ) {
    if (only != null && !only.contains(group)) {
      return;
    }
    for (final variant in _variants) {
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          final location = LocationWorld();
          location.places
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
              PlaceInfo(
                point: LatLng(51.5003, -0.1262),
                name: 'Westminster Abbey',
                address: 'Attraction',
                distanceMeters: 140,
              ),
              PlaceInfo(
                point: LatLng(51.4994, -0.1248),
                name: 'Houses of Parliament',
                address: 'Parliament Square',
                distanceMeters: 190,
              ),
            ]
            ..searchResults['big ben'] = const [
              PlaceInfo(
                point: LatLng(51.5007, -0.1246),
                name: 'Big Ben',
                address: 'Bridge Street, Westminster, London',
                distanceMeters: 20,
              ),
              PlaceInfo(
                point: LatLng(51.5008, -0.1247),
                name: 'Big Ben Café',
                address: 'Great George Street, London',
                distanceMeters: 60,
              ),
              PlaceInfo(
                point: LatLng(48.8584, 2.2945),
                name: 'Big Ben Pub',
                address: 'Rue de Rivoli, Paris',
                distanceMeters: 340000,
              ),
            ];
          world.extraOverrides = location.overrides;
          await open(tester, world, location, variant);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openChat(
    WidgetTester tester,
    PhoneWorld world, {
    bool cards = false,
    bool group = false,
  }) async {
    world.chats.messages = cards
        ? [
            phoneMessage('c1', bart, 'Where are we meeting?', minutesAgo: 30),
            phoneMessage(
              'c2',
              me,
              'Right by the clock tower, say hi when you see me',
              minutesAgo: 28,
            ),
            phoneMessage(
              'c3',
              bart,
              '📍 Big Ben · Westminster, London',
              minutesAgo: 25,
              attachment: const {
                'kind': 'location',
                'lat': 51.5007,
                'lng': -0.1246,
                'name': 'Big Ben',
                'address': 'Westminster, London',
              },
            ),
            phoneMessage(
              'c4',
              me,
              '📍 Westminster Abbey · 20 Dean\'s Yard, London',
              minutesAgo: 12,
              attachment: const {
                'kind': 'location',
                'lat': 51.4994,
                'lng': -0.1273,
                'name': 'Westminster Abbey',
                'address': '20 Dean\'s Yard, London',
              },
            ),
            phoneMessage(
              'c5',
              bart,
              '📍 Live location',
              minutesAgo: 4,
              attachment: {
                'kind': 'live_location',
                'share_id': 's-bart',
                'ends_at': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 41))
                    .toIso8601String(),
                'precise': true,
              },
            ),
            phoneMessage(
              'c6',
              bart,
              '📍 Live location',
              minutesAgo: 300,
              attachment: {
                'kind': 'live_location',
                'share_id': 's-old',
                'ends_at': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(hours: 2))
                    .toIso8601String(),
                'precise': false,
              },
            ),
          ]
        : [];
    await world.open(
      tester,
      '${ChatsScreen.path}/${group ? 'group-1' : 'dm-1'}',
      extra: ChatThreadRouteExtra(
        title: group ? 'Hiking club' : bart.displayName,
        type: group ? ConversationType.group : ConversationType.direct,
      ),
    );
    await settleMaps(tester);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
  }

  Future<void> openPicker(WidgetTester tester, PhoneWorld world) async {
    await openChat(tester, world);
    await openMenu(tester);
    await tester.tap(find.text('Location'));
    await settleMaps(tester);
  }

  screen('chat', 'chat-cards', (tester, world, location, variant) async {
    location.repository
      ..addShare(otherShare('s-bart', bart.id, bart.displayName))
      ..addShare(otherShare('s-grace', grace.id, 'Grace'));
    await openChat(tester, world, cards: true);
  });

  screen('menu', 'menu', (tester, world, location, variant) async {
    await openChat(tester, world);
    await openMenu(tester);
  });

  screen('picker', 'picker', (tester, world, location, variant) async {
    await openPicker(tester, world);
  });

  screen('search', 'picker-search', (tester, world, location, variant) async {
    await openPicker(tester, world);
    await tester.enterText(
      find.byKey(const ValueKey('location-search-field')),
      'big ben',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await settleMaps(tester);
  });

  screen('denied', 'picker-denied', (tester, world, location, variant) async {
    location.service
      ..current = LocationAccess.denied
      ..answerWhenAsked = LocationAccess.denied;
    await openPicker(tester, world);
  });

  screen('viewer', 'viewer', (tester, world, location, variant) async {
    world.chats.messages = [];
    await openChat(tester, world, cards: true);
    await tester.tap(find.byKey(const ValueKey('location-card')).first);
    await settleMaps(tester);
  });

  screen('consent', 'consent', (tester, world, location, variant) async {
    await openChat(tester, world, group: true);
    await openMenu(tester);
    await tester.tap(find.text('Share live location'));
    await settleMaps(tester);
  });

  screen('live', 'live-map', (tester, world, location, variant) async {
    final now = DateTime.now().toUtc();
    location.repository
      ..addShare(otherShare('s-bart', bart.id, bart.displayName))
      ..addShare(
        otherShare(
          's-grace',
          grace.id,
          'Grace',
          left: const Duration(hours: 5),
          precise: false,
        ),
      )
      ..addShare(
        otherShare('s-ada', 'user-9', 'Ada', left: const Duration(minutes: 12)),
      );
    await openChat(tester, world, cards: true, group: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await container
        .read(liveLocationSharerProvider.notifier)
        .start(
          conversationId: 'group-1',
          duration: const Duration(hours: 1),
          precise: true,
        );
    await settleMaps(tester);
    await tester.tap(find.byKey(const ValueKey('live-location-banner')));
    await settleMaps(tester);
    location.repository
        .channel('s-bart')
        .receive(
          LivePosition(
            point: const LatLng(51.5012, -0.1229),
            at: now,
            accuracyMeters: 8,
          ),
        );
    location.repository
        .channel('s-grace')
        .receive(
          LivePosition(
            point: const LatLng(51.4985, -0.1262),
            at: now.subtract(const Duration(seconds: 12)),
          ),
        );
    location.repository
        .channel('s-ada')
        .receive(
          LivePosition(
            point: const LatLng(51.5031, -0.1269),
            at: now.subtract(const Duration(minutes: 4)),
          ),
        );
    await settleMaps(tester);
    // The person moved a little.
    location.service.moveTo(const LatLng(51.5003, -0.1251));
    await settleMaps(tester);
  });
}
