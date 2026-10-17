import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:wecord/shared/models/message.dart';

/// A place on the map: what the picker returns and a location card holds.
class PlaceInfo {
  const PlaceInfo({
    required this.point,
    this.name = '',
    this.address = '',
    this.distanceMeters,
  });

  final LatLng point;

  /// "Big Ben", or empty for a dropped pin.
  final String name;

  /// "Westminster, London", or empty when none is known.
  final String address;

  /// How far it is from where the person is, when that is known (nearby
  /// lists).
  final double? distanceMeters;

  bool get hasName => name.trim().isNotEmpty;
  bool get hasAddress => address.trim().isNotEmpty;

  PlaceInfo copyWith({LatLng? point, String? name, String? address}) {
    return PlaceInfo(
      point: point ?? this.point,
      name: name ?? this.name,
      address: address ?? this.address,
      distanceMeters: distanceMeters,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaceInfo &&
      other.point == point &&
      other.name == name &&
      other.address == address;

  @override
  int get hashCode => Object.hash(point, name, address);
}

/// Whether [lat] and [lng] are on the globe (and not NaN).
bool isValidCoordinate(num? lat, num? lng) {
  if (lat == null || lng == null) {
    return false;
  }
  return lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;
}

/// A location card in a chat: a text message whose attachment is
/// `{kind: 'location', lat, lng, name, address}` (see `send_location` in
/// `202610180050_location.sql`). The body is a readable line, so previews,
/// pushes and search show something sensible.
class LocationAttachment {
  const LocationAttachment({
    required this.point,
    this.name = '',
    this.address = '',
  });

  final LatLng point;
  final String name;
  final String address;

  PlaceInfo get place => PlaceInfo(point: point, name: name, address: address);

  /// The card in a message, or null when [attachment] is not a (well formed)
  /// location.
  static LocationAttachment? maybeFromAttachment(
    Map<String, dynamic>? attachment,
  ) {
    if (attachment == null || attachment['kind'] != 'location') {
      return null;
    }
    final lat = attachment['lat'];
    final lng = attachment['lng'];
    if (lat is! num || lng is! num || !isValidCoordinate(lat, lng)) {
      return null;
    }
    String text(Object? value, int max) {
      final s = value is String ? value.trim() : '';
      return s.length > max ? s.substring(0, max) : s;
    }

    return LocationAttachment(
      point: LatLng(lat.toDouble(), lng.toDouble()),
      name: text(attachment['name'], 200),
      address: text(attachment['address'], 400),
    );
  }
}

/// A live location card: `{kind: 'live_location', share_id, ends_at,
/// precise}`. Whether it is still running comes from the share itself.
class LiveLocationAttachment {
  const LiveLocationAttachment({
    required this.shareId,
    required this.endsAt,
    required this.precise,
  });

  final String shareId;
  final DateTime endsAt;
  final bool precise;

  static LiveLocationAttachment? maybeFromAttachment(
    Map<String, dynamic>? attachment,
  ) {
    if (attachment == null || attachment['kind'] != 'live_location') {
      return null;
    }
    final id = attachment['share_id'];
    final endsAt = attachment['ends_at'];
    if (id is! String || id.isEmpty || endsAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(endsAt);
    if (parsed == null) {
      return null;
    }
    return LiveLocationAttachment(
      shareId: id,
      endsAt: parsed.toUtc(),
      precise: attachment['precise'] == true,
    );
  }
}

/// The location cards of a message.
extension LocationMessageCards on ChatMessage {
  /// The place this message shares, or null.
  LocationAttachment? get locationCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return LocationAttachment.maybeFromAttachment(attachment);
  }

  /// The live location this message announces, or null.
  LiveLocationAttachment? get liveLocationCard {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    return LiveLocationAttachment.maybeFromAttachment(attachment);
  }
}

/// A person sharing their location in a chat (a row of
/// `list_live_location_shares`).
class LiveShare {
  const LiveShare({
    required this.id,
    required this.userId,
    required this.name,
    required this.messageId,
    required this.precise,
    required this.startedAt,
    required this.endsAt,
    this.avatarUrl,
  });

  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String? messageId;
  final bool precise;
  final DateTime startedAt;
  final DateTime endsAt;

  bool isRunningAt(DateTime now) => now.isBefore(endsAt);

  factory LiveShare.fromJson(Map<String, dynamic> json) {
    return LiveShare(
      id: json['share_id'] as String,
      userId: json['user_id'] as String,
      name: (json['display_name'] as String?)?.trim().isNotEmpty == true
          ? (json['display_name'] as String).trim()
          : '?',
      avatarUrl: json['avatar_url'] as String?,
      messageId: json['message_id'] as String?,
      precise: json['precise'] == true,
      startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
      endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveShare &&
      other.id == id &&
      other.userId == userId &&
      other.endsAt == endsAt &&
      other.precise == precise &&
      other.name == name &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, userId, endsAt, precise, name, avatarUrl);
}

/// A share of the signed-in person that this device is sending positions for.
class OwnShare {
  const OwnShare({
    required this.shareId,
    required this.conversationId,
    required this.endsAt,
    required this.precise,
    this.lastPoint,
    this.lastSentAt,
  });

  final String shareId;
  final String conversationId;
  final DateTime endsAt;

  /// Whether exact positions go out (otherwise coarse ones).
  final bool precise;

  /// The last position that went out (already coarsened when it is).
  final LatLng? lastPoint;
  final DateTime? lastSentAt;

  factory OwnShare.fromJson(Map<String, dynamic> json) {
    return OwnShare(
      shareId: json['share_id'] as String,
      conversationId: json['conversation_id'] as String,
      endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
      precise: json['precise'] == true,
    );
  }

  Duration remaining(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  OwnShare copyWith({LatLng? lastPoint, DateTime? lastSentAt}) {
    return OwnShare(
      shareId: shareId,
      conversationId: conversationId,
      endsAt: endsAt,
      precise: precise,
      lastPoint: lastPoint ?? this.lastPoint,
      lastSentAt: lastSentAt ?? this.lastSentAt,
    );
  }
}

/// One position of someone sharing, as it travels on the share's channel.
class LivePosition {
  const LivePosition({
    required this.point,
    required this.at,
    this.accuracyMeters,
    this.heading,
  });

  final LatLng point;
  final DateTime at;
  final double? accuracyMeters;

  /// Degrees clockwise from north, when moving.
  final double? heading;

  Map<String, dynamic> toPayload() => {
    'lat': point.latitude,
    'lng': point.longitude,
    'at': at.toUtc().millisecondsSinceEpoch,
    'acc': ?accuracyMeters,
    'hdg': ?heading,
  };

  static LivePosition? maybeFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) {
      return null;
    }
    final lat = payload['lat'];
    final lng = payload['lng'];
    final at = payload['at'];
    if (lat is! num || lng is! num || !isValidCoordinate(lat, lng)) {
      return null;
    }
    final acc = payload['acc'];
    final hdg = payload['hdg'];
    return LivePosition(
      point: LatLng(lat.toDouble(), lng.toDouble()),
      at: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true)
          : DateTime.now().toUtc(),
      accuracyMeters: acc is num && acc.isFinite ? acc.toDouble() : null,
      heading: hdg is num && hdg.isFinite ? hdg.toDouble() : null,
    );
  }
}

/// What to send when someone does not share an exact position: the
/// position snapped to a grid of about 500 m, so nothing finer ever leaves
/// the device.
LatLng coarsen(LatLng point) {
  const step = 0.005; // about 550 m of latitude
  double snap(double value) => (value / step).round() * step;
  return LatLng(
    snap(point.latitude).clamp(-90.0, 90.0),
    snap(point.longitude).clamp(-180.0, 180.0),
  );
}

/// The great-circle distance between two points, in meters.
double distanceMeters(LatLng a, LatLng b) {
  const earth = 6371008.8;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earth * math.asin(math.min(1, math.sqrt(h)));
}

/// "25 m", "1.2 km".
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded = meters < 100
        ? (meters / 5).round() * 5
        : (meters / 10).round() * 10;
    return '${rounded < 5 ? 5 : rounded} m';
  }
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}
