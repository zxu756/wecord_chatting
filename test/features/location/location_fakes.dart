import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_repository.dart';
import 'package:wecord/features/location/location_service.dart';
import 'package:wecord/features/location/map_config.dart';
import 'package:wecord/features/location/open_in_maps.dart';
import 'package:wecord/features/location/places_service.dart';

/// Where the fakes put the person: Westminster, London.
const westminster = LatLng(51.5007, -0.1246);

/// Map tiles drawn here instead of fetched: a pale street plan with parks
/// and water, so no map test reaches the network.
class FakeTileProvider extends TileProvider {
  static final _tiles = <int, Uint8List>{};

  static Uint8List _tile(int variant) {
    return _tiles.putIfAbsent(variant, () {
      final random = math.Random(variant);
      final tile = img.Image(width: 256, height: 256);
      img.fill(tile, color: img.ColorRgb8(238, 234, 224));
      // Parks and water.
      for (var i = 0; i < 3; i++) {
        final x = random.nextInt(180);
        final y = random.nextInt(180);
        final green = i == 0;
        img.fillRect(
          tile,
          x1: x,
          y1: y,
          x2: x + 40 + random.nextInt(60),
          y2: y + 30 + random.nextInt(50),
          color: green
              ? img.ColorRgb8(200, 222, 188)
              : img.ColorRgb8(170, 205, 228),
          radius: 8,
        );
      }
      // Streets.
      for (var i = 0; i < 4; i++) {
        final y = 20 + random.nextInt(216);
        img.drawLine(
          tile,
          x1: 0,
          y1: y,
          x2: 255,
          y2: y + random.nextInt(40) - 20,
          color: img.ColorRgb8(255, 255, 255),
          thickness: 6,
        );
        final x = 20 + random.nextInt(216);
        img.drawLine(
          tile,
          x1: x,
          y1: 0,
          x2: x + random.nextInt(40) - 20,
          y2: 255,
          color: img.ColorRgb8(250, 244, 226),
          thickness: 5,
        );
      }
      return Uint8List.fromList(img.encodePng(tile));
    });
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(
      _tile((coordinates.x * 7 + coordinates.y * 3).abs() % 6),
    );
  }
}

class FakeLocationService implements LocationService {
  FakeLocationService({
    this.current = LocationAccess.granted,
    DevicePosition? position,
  }) : position =
           position ??
           DevicePosition(
             point: westminster,
             at: DateTime.utc(2026, 10, 18, 12),
             accuracyMeters: 12,
           );

  LocationAccess current;

  /// What the system prompt answers when the person is asked.
  LocationAccess answerWhenAsked = LocationAccess.granted;
  DevicePosition position;
  var requests = 0;
  var settingsOpened = 0;
  var currentCalls = 0;
  final _stream = StreamController<DevicePosition>.broadcast();
  final streamPrecise = <bool>[];

  /// Whether anything follows the person right now.
  bool get following => _stream.hasListener;

  /// Moves the person.
  void moveTo(LatLng point) {
    position = DevicePosition(point: point, at: clock.now().toUtc());
    _stream.add(position);
  }

  @override
  Future<LocationAccess> access() async => current;

  @override
  Future<LocationAccess> requestAccess() async {
    requests += 1;
    if (current == LocationAccess.denied) {
      current = answerWhenAsked;
    }
    return current;
  }

  @override
  Future<DevicePosition> currentPosition({bool precise = true}) async {
    currentCalls += 1;
    if (current != LocationAccess.granted) {
      throw const LocationUnavailable('not allowed');
    }
    return position;
  }

  @override
  Stream<DevicePosition> positions({
    bool precise = true,
    int minDistanceMeters = 10,
  }) {
    streamPrecise.add(precise);
    return _stream.stream;
  }

  @override
  Future<void> openSettings() async => settingsOpened += 1;
}

class FakePlacesService implements PlacesService {
  List<PlaceInfo> nearbyPlaces = const [];
  Map<String, List<PlaceInfo>> searchResults = {};
  PlaceInfo? reverseResult;
  Object? failNearby;
  Object? failSearch;
  final searches = <String>[];
  final reversed = <LatLng>[];

  @override
  Future<List<PlaceInfo>> nearby(LatLng point) async {
    if (failNearby != null) {
      throw failNearby!;
    }
    return nearbyPlaces;
  }

  @override
  Future<PlaceInfo?> reverse(LatLng point) async {
    reversed.add(point);
    return reverseResult;
  }

  @override
  Future<List<PlaceInfo>> search(String query, {LatLng? near}) async {
    searches.add(query);
    if (failSearch != null) {
      throw failSearch!;
    }
    return searchResults[query] ?? const [];
  }
}

/// A share's channel in memory: tests push positions in with [receive] and
/// read what this device sent from [sent].
class FakePositionChannel implements LivePositionChannel {
  final _positions = StreamController<LivePosition>.broadcast();
  final _requests = StreamController<void>.broadcast();
  final _joined = StreamController<bool>.broadcast();
  final sent = <LivePosition>[];
  var latestRequests = 0;
  var closed = false;
  var isJoined = true;

  void receive(LivePosition position) => _positions.add(position);

  /// A listener joined and asks for the latest position.
  void listenerJoined() => _requests.add(null);

  void refuse() {
    isJoined = false;
    _joined.add(false);
  }

  @override
  Stream<LivePosition> get positions => _positions.stream;

  @override
  Stream<void> get requests => _requests.stream;

  @override
  Stream<bool> get joined async* {
    if (isJoined) {
      yield true;
    }
    yield* _joined.stream;
  }

  @override
  Future<void> send(LivePosition position) async => sent.add(position);

  @override
  Future<void> requestLatest() async => latestRequests += 1;

  @override
  Future<void> close() async {
    closed = true;
  }
}

class FakeLocationRepository implements LocationRepository {
  /// Locations sent: (chat, place).
  final sentLocations = <(String, PlaceInfo)>[];
  Object? failSend;
  Object? failStart;

  /// Every share, running or not, as the server would hold it.
  final shares = <LiveShare>[];
  final started = <(String, int, bool)>[];
  final stopped = <String>[];
  var stopAllCalls = 0;
  final channels = <String, FakePositionChannel>{};
  final _changes = StreamController<String>.broadcast();
  var _counter = 0;

  /// The share ids [listMyShares] answers (a restarted app).
  List<OwnShare> mine = [];

  FakePositionChannel channel(String shareId) =>
      channels.putIfAbsent(shareId, FakePositionChannel.new);

  /// Another person starts sharing.
  void addShare(LiveShare share) {
    shares.add(share);
    _changes.add(share.messageId ?? '');
  }

  void pingChanged() => _changes.add('');

  @override
  Future<String?> sendLocation(String conversationId, PlaceInfo place) async {
    if (failSend != null) {
      throw failSend!;
    }
    sentLocations.add((conversationId, place));
    return 'location-message-${sentLocations.length}';
  }

  @override
  Future<List<LiveShare>> listShares(String conversationId) async {
    final now = clock.now().toUtc();
    return [
      for (final share in shares)
        if (share.isRunningAt(now) && !stopped.contains(share.id)) share,
    ];
  }

  @override
  Future<List<OwnShare>> listMyShares() async => mine;

  @override
  Future<StartedShare> startShare({
    required String conversationId,
    required int durationMinutes,
    required bool precise,
  }) async {
    if (failStart != null) {
      throw failStart!;
    }
    started.add((conversationId, durationMinutes, precise));
    _counter += 1;
    final endsAt = clock.now().toUtc().add(Duration(minutes: durationMinutes));
    final share = StartedShare(
      shareId: 'share-mine-$_counter',
      messageId: 'live-message-$_counter',
      endsAt: endsAt,
    );
    shares.add(
      LiveShare(
        id: share.shareId,
        userId: 'user-1',
        name: 'Me',
        messageId: share.messageId,
        precise: precise,
        startedAt: clock.now().toUtc(),
        endsAt: endsAt,
      ),
    );
    _changes.add(conversationId);
    return share;
  }

  @override
  Future<void> stopShare(String shareId) async {
    stopped.add(shareId);
    _changes.add('');
  }

  @override
  Future<void> stopAll() async => stopAllCalls += 1;

  @override
  Stream<void> sharesChanged(String conversationId) =>
      _changes.stream.map((_) {});

  @override
  LivePositionChannel openChannel(String shareId) => channel(shareId);
}

class FakeMapsLauncher implements MapsLauncher {
  final opened = <Uri>[];
  final copied = <String>[];
  bool succeeds = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }

  @override
  Future<void> copy(String text) async => copied.add(text);
}

/// Everything the location screens talk to, as fakes.
class LocationWorld {
  LocationWorld({
    FakeLocationService? service,
    FakePlacesService? places,
    FakeLocationRepository? repository,
    FakeMapsLauncher? launcher,
    this.isWeb = false,
  }) : service = service ?? FakeLocationService(),
       places = places ?? FakePlacesService(),
       repository = repository ?? FakeLocationRepository(),
       launcher = launcher ?? FakeMapsLauncher();

  final FakeLocationService service;
  final FakePlacesService places;
  final FakeLocationRepository repository;
  final FakeMapsLauncher launcher;
  final bool isWeb;

  List<Override> get overrides => [
    locationServiceProvider.overrideWithValue(service),
    placesServiceProvider.overrideWithValue(places),
    locationRepositoryProvider.overrideWithValue(repository),
    mapsLauncherProvider.overrideWithValue(launcher),
    mapsIsWebProvider.overrideWithValue(isWeb),
    mapTileProviderProvider.overrideWithValue(FakeTileProvider()),
    mapConfigProvider.overrideWithValue(
      const MapConfig(tileUrl: 'https://tiles.example.test/{z}/{x}/{y}.png'),
    ),
  ];
}

/// A live share of somebody else.
LiveShare otherShare(
  String id,
  String userId,
  String name, {
  Duration left = const Duration(minutes: 40),
  bool precise = true,
  String? messageId,
}) {
  final now = clock.now().toUtc();
  return LiveShare(
    id: id,
    userId: userId,
    name: name,
    messageId: messageId ?? 'card-$id',
    precise: precise,
    startedAt: now.subtract(const Duration(minutes: 5)),
    endsAt: now.add(left),
  );
}

/// Lets images decode and animations run, which `pump` alone does not.
Future<void> settleMaps(WidgetTester tester) async {
  for (var round = 0; round < 4; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
