import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_service.dart';
import 'package:wecord/features/location/map_widgets.dart';
import 'package:wecord/features/location/static_map.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mobile/phone_test_support.dart';
import 'location_fakes.dart';

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  LocationWorld location, {
  String id = 'dm-1',
  ConversationType type = ConversationType.direct,
  List<ChatMessage>? messages,
}) async {
  world.chats.messages = messages ?? [];
  world.extraOverrides = location.overrides;
  await world.open(
    tester,
    '${ChatsScreen.path}/$id',
    extra: ChatThreadRouteExtra(title: 'Hiking club', type: type),
  );
  await settleMaps(tester);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
  await settle(tester);
}

ChatMessage _locationCard(String id, Profile sender, {int minutesAgo = 5}) {
  return phoneMessage(
    id,
    sender,
    '📍 Big Ben · Westminster, London',
    minutesAgo: minutesAgo,
    attachment: const {
      'kind': 'location',
      'lat': 51.5007,
      'lng': -0.1246,
      'name': 'Big Ben',
      'address': 'Westminster, London',
    },
  );
}

ChatMessage _liveCard(
  String id,
  Profile sender,
  String shareId, {
  int minutesAgo = 3,
  String conversationId = 'dm-1',
}) {
  return phoneMessage(
    id,
    sender,
    '📍 Live location',
    minutesAgo: minutesAgo,
    conversationId: conversationId,
    attachment: {
      'kind': 'live_location',
      'share_id': shareId,
      'ends_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'precise': true,
    },
  );
}

void main() {
  late PhoneWorld world;
  late LocationWorld location;

  setUp(() {
    AppStrings.isChinese = false;
    world = PhoneWorld();
    location = LocationWorld();
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
      ];
  });

  group('the + menu', () {
    testWidgets('direct chats offer Location and Share live location', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(tester, world, location);
      await _openMenu(tester);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Share live location'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('groups do too', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(
        tester,
        world,
        location,
        id: 'group-1',
        type: ConversationType.group,
      );
      await _openMenu(tester);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Share live location'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a channel can send a place but not share live', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      world.chats.messages = [];
      world.extraOverrides = location.overrides;
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-general',
        extra: const ChatThreadRouteExtra(
          title: '# general',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );
      await settleMaps(tester);
      await _openMenu(tester);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Share live location'), findsNothing);
      await world.close(tester);
    });
  });

  group('sending a location', () {
    testWidgets('Location opens the map, Send posts the card to this chat', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(tester, world, location);
      await _openMenu(tester);
      await tester.tap(find.text('Location'));
      await settleMaps(tester);

      expect(find.text('Send location'), findsOneWidget);
      expect(find.text('Current location'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('location-send')));
      await settleMaps(tester);

      final (chat, place) = location.repository.sentLocations.single;
      expect(chat, 'dm-1');
      expect(place.name, 'Bridge Street');
      expect(place.address, 'Westminster, London');
      expect(place.point.latitude, closeTo(51.5007, 1e-3));
      expect(find.text('Send location'), findsNothing);
      await world.close(tester);
    });

    testWidgets('backing out sends nothing', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(tester, world, location);
      await _openMenu(tester);
      await tester.tap(find.text('Location'));
      await settleMaps(tester);
      await tester.tap(find.byKey(const ValueKey('location-picker-close')));
      await settleMaps(tester);
      expect(location.repository.sentLocations, isEmpty);
      await world.close(tester);
    });

    testWidgets('a send that fails says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      location.repository.failSend = Exception('offline');
      await _open(tester, world, location);
      await _openMenu(tester);
      await tester.tap(find.text('Location'));
      await settleMaps(tester);
      await tester.tap(find.byKey(const ValueKey('location-send')));
      await settleMaps(tester);
      expect(
        find.text("Couldn't send the location. Try again."),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });

  group('location cards in the conversation', () {
    testWidgets('show the place on a small map with its name and address', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(
        tester,
        world,
        location,
        messages: [_locationCard('loc-1', bart)],
      );
      expect(find.byKey(const ValueKey('location-card')), findsOneWidget);
      expect(find.text('Big Ben'), findsOneWidget);
      expect(find.text('Westminster, London'), findsOneWidget);
      // A picture of the map with the pin, not a live map.
      expect(find.byType(StaticMap), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byType(MapPin), findsOneWidget);
      // The readable line is not shown on top of the card.
      expect(find.textContaining('📍'), findsNothing);
      await world.close(tester);
    });

    testWidgets(
      'tapping a card opens the full map with Open in Maps and Copy',
      (tester) async {
        usePhoneViewport(tester, notchedPhone);
        await _open(
          tester,
          world,
          location,
          messages: [_locationCard('loc-1', bart)],
        );
        await tester.tap(find.byKey(const ValueKey('location-card')));
        await settleMaps(tester);

        expect(
          find.byKey(const ValueKey('location-viewer-map')),
          findsOneWidget,
        );
        expect(find.text('Shared by ${bart.displayName}'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('location-open-in-maps')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('location-copy-address')),
          findsOneWidget,
        );
        await world.close(tester);
      },
    );

    testWidgets('your own card has no Edit, others have Copy', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(
        tester,
        world,
        location,
        messages: [_locationCard('loc-1', me)],
      );
      await tester.longPress(find.byKey(const ValueKey('location-card')));
      await settle(tester);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Copy'), findsWidgets);
      await world.close(tester);
    });
  });

  group('live location in a chat', () {
    testWidgets(
      'Share live location asks first, then starts and opens the map',
      (tester) async {
        usePhoneViewport(tester, notchedPhone);
        await _open(tester, world, location);
        await _openMenu(tester);
        await tester.tap(find.text('Share live location'));
        await settleMaps(tester);

        // Consent comes before anything is shared.
        expect(find.byKey(const ValueKey('live-start')), findsOneWidget);
        expect(location.repository.started, isEmpty);
        expect(
          find.text('Sharing pauses when WeCord is closed.'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('live-duration-60')));
        await settleMaps(tester);
        await tester.tap(find.byKey(const ValueKey('live-start')));
        await settleMaps(tester);

        expect(location.repository.started, [('dm-1', 60, false)]);
        // The map of everyone sharing opens, with you on it.
        expect(find.byKey(const ValueKey('live-location-map')), findsOneWidget);
        expect(find.text("1 person sharing location"), findsOneWidget);
        await world.close(tester);
      },
    );

    testWidgets('consent every time: cancelling shares nothing', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(tester, world, location);
      await _openMenu(tester);
      await tester.tap(find.text('Share live location'));
      await settleMaps(tester);
      await tester.tap(find.byKey(const ValueKey('live-cancel')));
      await settleMaps(tester);
      expect(location.repository.started, isEmpty);
      expect(location.service.requests, 0);
      expect(find.byKey(const ValueKey('live-location-banner')), findsNothing);
      await world.close(tester);
    });

    testWidgets('without permission nothing is shared and the person is told', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      location.service
        ..current = LocationAccess.denied
        ..answerWhenAsked = LocationAccess.denied;
      await _open(tester, world, location);
      await _openMenu(tester);
      await tester.tap(find.text('Share live location'));
      await settleMaps(tester);
      await tester.tap(find.byKey(const ValueKey('live-start')));
      await settleMaps(tester);
      expect(location.repository.started, isEmpty);
      expect(
        find.text('WeCord needs your location to share it.'),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a banner shows who is sharing and opens the map', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      location.repository
        ..addShare(otherShare('s-bart', bart.id, 'Bart the Bold'))
        ..addShare(otherShare('s-grace', grace.id, 'Grace'));
      await _open(tester, world, location);
      expect(find.text('2 people sharing location'), findsOneWidget);
      expect(find.textContaining('Bart the Bold, Grace'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('live-location-banner')));
      await settleMaps(tester);
      expect(find.byKey(const ValueKey('live-location-map')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('the banner follows people starting and stopping', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(tester, world, location);
      expect(find.byKey(const ValueKey('live-location-banner')), findsNothing);

      location.repository.addShare(
        otherShare('s-bart', bart.id, 'Bart the Bold'),
      );
      await tester.pump(const Duration(seconds: 1));
      await settleMaps(tester);
      expect(find.text('1 person sharing location'), findsOneWidget);

      location.repository.stopped.add('s-bart');
      location.repository.pingChanged();
      await tester.pump(const Duration(seconds: 1));
      await settleMaps(tester);
      expect(find.byKey(const ValueKey('live-location-banner')), findsNothing);
      await world.close(tester);
    });

    testWidgets('your own sharing has Stop in the banner, which ends it', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _open(tester, world, location);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      await container
          .read(liveLocationSharerProvider.notifier)
          .start(
            conversationId: 'dm-1',
            duration: const Duration(minutes: 15),
            precise: true,
          );
      await settleMaps(tester);
      expect(find.text("You're sharing your location"), findsOneWidget);
      expect(find.textContaining('min left'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('live-banner-stop')));
      await settleMaps(tester);
      expect(location.repository.stopped, hasLength(1));
      expect(find.byKey(const ValueKey('live-location-banner')), findsNothing);
      expect(location.service.following, isFalse);
      await world.close(tester);
    });

    testWidgets(
      'a live card says who shares and for how long, then that it ended',
      (tester) async {
        usePhoneViewport(tester, notchedPhone);
        location.repository.addShare(
          otherShare(
            's-bart',
            bart.id,
            'Bart the Bold',
            left: const Duration(minutes: 40),
          ),
        );
        await _open(
          tester,
          world,
          location,
          messages: [
            _liveCard('live-1', bart, 's-bart'),
            _liveCard('live-0', bart, 's-old', minutesAgo: 400),
          ],
        );
        expect(find.text('Live location'), findsOneWidget);
        expect(find.textContaining('is sharing'), findsWidgets);
        expect(find.textContaining('min left'), findsWidgets);
        // The older one is over.
        expect(find.text('Live location ended'), findsOneWidget);
        expect(
          find.text('${bart.displayName} stopped sharing'),
          findsOneWidget,
        );

        await tester.tap(find.text('Live location'));
        await settleMaps(tester);
        expect(find.byKey(const ValueKey('live-location-map')), findsOneWidget);
        await world.close(tester);
      },
    );

    testWidgets('a card cannot borrow somebody else\'s share', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      // Grace shares; a card from Bart names Grace's share.
      location.repository.addShare(otherShare('s-grace', grace.id, 'Grace'));
      await _open(
        tester,
        world,
        location,
        messages: [_liveCard('live-1', bart, 's-grace')],
      );
      expect(find.text('Live location ended'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('live cards cannot be edited or forwarded', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      location.repository.addShare(
        otherShare('s-me', me.id, 'Me', left: const Duration(minutes: 40)),
      );
      await _open(
        tester,
        world,
        location,
        messages: [_liveCard('live-1', me, 's-me')],
      );
      await tester.longPress(find.byKey(const ValueKey('live-location-card')));
      await settle(tester);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Forward'), findsNothing);
      await world.close(tester);
    });
  });
}
