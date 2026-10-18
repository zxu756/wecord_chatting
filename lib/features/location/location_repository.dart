import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/realtime/private_channels.dart';

/// A share the server just started (`start_live_location`).
class StartedShare {
  const StartedShare({
    required this.shareId,
    required this.messageId,
    required this.endsAt,
  });

  final String shareId;
  final String messageId;
  final DateTime endsAt;
}

/// Why the server turned a send or a share down, in a form a screen can word.
class LocationRefused implements Exception {
  const LocationRefused(this.reason);

  final String reason;

  @override
  String toString() => 'LocationRefused($reason)';
}

/// One share's private channel: positions go out on it from the person
/// sharing and arrive from everyone sharing. Nothing sent here is stored.
abstract interface class LivePositionChannel {
  /// Positions as they arrive from the person sharing.
  Stream<LivePosition> get positions;

  /// A listener who has just joined and wants the latest position (sent to
  /// the person sharing, who answers at once instead of at the next tick).
  Stream<void> get requests;

  /// Whether the channel is joined (the server let this person in): true
  /// once it is (at once when it already is), false when it is refused or
  /// drops.
  Stream<bool> get joined;

  /// Sends a position to the listeners. Only the person sharing may.
  Future<void> send(LivePosition position);

  /// Asks the person sharing for the latest position.
  Future<void> requestLatest();

  Future<void> close();
}

/// The server side of locations: cards, who is sharing and the channels
/// positions travel on. Every call is the signed-in person's own.
abstract interface class LocationRepository {
  /// Posts a location card (`send_location`); returns the message id.
  Future<String?> sendLocation(String conversationId, PlaceInfo place);

  /// The shares running in a chat that this person may see.
  Future<List<LiveShare>> listShares(String conversationId);

  /// The shares this person has running, in any chat.
  Future<List<OwnShare>> listMyShares();

  /// Starts sharing in a chat and posts the card.
  Future<StartedShare> startShare({
    required String conversationId,
    required int durationMinutes,
    required bool precise,
  });

  Future<void> stopShare(String shareId);

  /// Stops everything this person is sharing (signing out).
  Future<void> stopAll();

  /// Pings when shares of a chat started or stopped.
  Stream<void> sharesChanged(String conversationId);

  /// Joins the share's channel.
  LivePositionChannel openChannel(String shareId);
}

class SupabaseLocationRepository implements LocationRepository {
  const SupabaseLocationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> sendLocation(String conversationId, PlaceInfo place) async {
    try {
      final id = await _client.rpc<String?>(
        'send_location',
        params: {
          'target_conversation_id': conversationId,
          'place_lat': place.point.latitude,
          'place_lng': place.point.longitude,
          'place_name': place.name,
          'place_address': place.address,
        },
      );
      return id;
    } on PostgrestException catch (error) {
      throw LocationRefused(error.message);
    }
  }

  @override
  Future<List<LiveShare>> listShares(String conversationId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_live_location_shares',
      params: {'target_conversation_id': conversationId},
    );
    return [
      for (final row in rows)
        LiveShare.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<List<OwnShare>> listMyShares() async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_my_live_location_shares',
    );
    return [
      for (final row in rows)
        OwnShare.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<StartedShare> startShare({
    required String conversationId,
    required int durationMinutes,
    required bool precise,
  }) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'start_live_location',
        params: {
          'target_conversation_id': conversationId,
          'duration_minutes': durationMinutes,
          'precise': precise,
        },
      );
      final row = Map<String, dynamic>.from(rows.first as Map);
      return StartedShare(
        shareId: row['share_id'] as String,
        messageId: row['message_id'] as String,
        endsAt: DateTime.parse(row['ends_at'] as String).toUtc(),
      );
    } on PostgrestException catch (error) {
      throw LocationRefused(error.message);
    }
  }

  @override
  Future<void> stopShare(String shareId) async {
    await _client.rpc<void>(
      'stop_live_location',
      params: {'target_share_id': shareId},
    );
  }

  @override
  Future<void> stopAll() async {
    await _client.rpc<void>('stop_my_live_locations');
  }

  @override
  Stream<void> sharesChanged(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('live-shares-$conversationId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'live_location_shares',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: conversationId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  LivePositionChannel openChannel(String shareId) {
    return _SupabasePositionChannel(_client, shareId);
  }
}

/// The share's private broadcast channel (`live-location:<id>`), whose
/// access the policies of `202610180050_location.sql` decide.
class _SupabasePositionChannel implements LivePositionChannel {
  _SupabasePositionChannel(this._client, String shareId) {
    _channel = _client
        .channel(liveLocationTopic(shareId), opts: privateChannelConfig())
        .onBroadcast(
          event: 'pos',
          callback: (payload) {
            final position = LivePosition.maybeFromPayload(payload);
            if (position != null && !_positions.isClosed) {
              _positions.add(position);
            }
          },
        )
        .onBroadcast(
          event: 'hello',
          callback: (_) {
            if (!_requests.isClosed) {
              _requests.add(null);
            }
          },
        )
        .subscribe((status, error) {
          if (_joined.isClosed) {
            return;
          }
          if (status == RealtimeSubscribeStatus.subscribed) {
            _isJoined = true;
            _joined.add(true);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            _isJoined = false;
            _joined.add(false);
          }
        });
  }

  final SupabaseClient _client;
  late final RealtimeChannel _channel;
  final _positions = StreamController<LivePosition>.broadcast();
  final _requests = StreamController<void>.broadcast();
  final _joined = StreamController<bool>.broadcast();
  var _isJoined = false;

  @override
  Stream<LivePosition> get positions => _positions.stream;

  @override
  Stream<void> get requests => _requests.stream;

  @override
  Stream<bool> get joined async* {
    if (_isJoined) {
      yield true;
    }
    yield* _joined.stream;
  }

  @override
  Future<void> send(LivePosition position) async {
    if (!_isJoined) {
      return;
    }
    await _channel.sendBroadcastMessage(
      event: 'pos',
      payload: position.toPayload(),
    );
  }

  @override
  Future<void> requestLatest() async {
    if (!_isJoined) {
      return;
    }
    await _channel.sendBroadcastMessage(event: 'hello', payload: {});
  }

  @override
  Future<void> close() async {
    await _positions.close();
    await _requests.close();
    await _joined.close();
    await _client.removeChannel(_channel);
  }
}

/// Stands in before Supabase is set up (tests): nobody shares.
class UninitializedLocationRepository implements LocationRepository {
  const UninitializedLocationRepository();

  @override
  Future<String?> sendLocation(String conversationId, PlaceInfo place) {
    throw StateError('Supabase must be initialized to send a location.');
  }

  @override
  Future<List<LiveShare>> listShares(String conversationId) async => const [];

  @override
  Future<List<OwnShare>> listMyShares() async => const [];

  @override
  Future<StartedShare> startShare({
    required String conversationId,
    required int durationMinutes,
    required bool precise,
  }) {
    throw StateError('Supabase must be initialized to share a location.');
  }

  @override
  Future<void> stopShare(String shareId) async {}

  @override
  Future<void> stopAll() async {}

  @override
  Stream<void> sharesChanged(String conversationId) =>
      const Stream<void>.empty();

  @override
  LivePositionChannel openChannel(String shareId) {
    throw StateError('Supabase must be initialized to share a location.');
  }
}

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  try {
    return SupabaseLocationRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedLocationRepository();
  }
});
