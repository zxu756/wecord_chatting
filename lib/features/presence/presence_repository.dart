import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/presence/presence_feed.dart';
import 'package:wecord/features/presence/presence_heartbeat.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/app_visibility.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/realtime/private_channels.dart';

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) {
  try {
    return SupabasePresenceRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedPresenceRepository();
  }
});

/// The current user's status and the show-online switch, loaded from the
/// server for whoever is signed in. Defaults (online, shown) until loaded,
/// or when they can't be read.
final presenceSettingsProvider =
    AsyncNotifierProvider<PresenceSettingsController, PresenceSettings>(
      PresenceSettingsController.new,
    );

class PresenceSettingsController extends AsyncNotifier<PresenceSettings> {
  @override
  Future<PresenceSettings> build() async {
    final userId = ref.watch(
      authStateProvider.select((state) => state.value?.id),
    );
    if (userId == null) {
      return const PresenceSettings();
    }
    try {
      return await ref.watch(presenceRepositoryProvider).loadSettings();
    } catch (_) {
      // Fall back to the default (visible) when the settings can't be read.
      return const PresenceSettings();
    }
  }

  /// Shows [status] at once and saves it; puts the old one back and
  /// rethrows when saving fails.
  Future<void> setStatus(PresenceStatus status) {
    return _save(
      (settings) => settings.copyWith(status: status),
      (repository) => repository.setStatus(status),
    );
  }

  Future<void> setShowOnlineStatus(bool show) {
    return _save(
      (settings) => settings.copyWith(showOnlineStatus: show),
      (repository) => repository.setShowOnlineStatus(show),
    );
  }

  Future<void> _save(
    PresenceSettings Function(PresenceSettings settings) change,
    Future<void> Function(PresenceRepository repository) save,
  ) async {
    final previous = state.value ?? const PresenceSettings();
    state = AsyncData(change(previous));
    try {
      await save(ref.read(presenceRepositoryProvider));
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

/// True after a while without keyboard or pointer input on desktop and web
/// (see PresenceActivityListener); an Online user then shows as Idle.
final presenceInactiveProvider = StateProvider<bool>((ref) => false);

/// How others see the current user right now, or null while they appear
/// offline (Invisible, or online status hidden). Null until their settings
/// have loaded.
final broadcastPresenceProvider = Provider<PresenceStatus?>((ref) {
  final settings = ref.watch(presenceSettingsProvider).value;
  if (settings == null || settings.hidden) {
    return null;
  }
  if (settings.status == PresenceStatus.online &&
      ref.watch(presenceInactiveProvider)) {
    return PresenceStatus.idle;
  }
  return settings.status;
});

/// How the current user sees themselves: Invisible while hidden from
/// others, Idle when away from the keyboard.
final ownPresenceProvider = Provider<PresenceStatus>((ref) {
  final settings =
      ref.watch(presenceSettingsProvider).value ?? const PresenceSettings();
  if (settings.hidden) {
    return PresenceStatus.invisible;
  }
  return ref.watch(broadcastPresenceProvider) ?? settings.status;
});

/// The people the signed-in user may see who have the app open right now,
/// with their status: friends, members of a shared circle, group or direct
/// chat; never someone blocked either way or someone who hides their online
/// status. The server decides who (see [PresenceRepository.statuses]). The
/// shell keeps this running for as long as someone is signed in; everything
/// else just reads it.
final presenceStatusesProvider =
    StreamProvider.autoDispose<Map<String, PresenceStatus>>((ref) {
      final userId = ref.watch(
        authStateProvider.select((state) => state.value?.id),
      );
      if (userId == null) {
        return Stream.value(const <String, PresenceStatus>{});
      }
      final ownStatus = ValueNotifier<PresenceStatus?>(
        ref.read(broadcastPresenceProvider),
      );
      ref.listen(broadcastPresenceProvider, (previous, next) {
        ownStatus.value = next;
      });
      // A presence sync that changes nothing (they come after every join,
      // leave and re-announce) is not news to the screens watching this.
      return ref
          .watch(presenceRepositoryProvider)
          .statuses(ownStatus)
          .distinct(mapEquals);
    });

/// Ids of users who have the app open right now (see
/// [presenceStatusesProvider]).
final onlineUserIdsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  // Follows who is here, not how present they are: someone going Idle or
  // back does not change this, and the screens watching it (every chat,
  // sidebar and member list) should not rebuild for it.
  final online = ref.watch(
    presenceStatusesProvider.select((statuses) {
      final value = statuses.value;
      return value == null ? null : (value.keys.toList()..sort()).join('\n');
    }),
  );
  return online == null
      ? const Stream<Set<String>>.empty()
      : Stream.value(online.isEmpty ? <String>{} : online.split('\n').toSet());
});

/// [userId]'s status for others to see: null while offline (or invisible),
/// otherwise Online unless they said otherwise. [statuses] may be null
/// while loading; [onlineUserIds] decides who is online.
PresenceStatus? presenceOf(
  String? userId, {
  required Set<String> onlineUserIds,
  Map<String, PresenceStatus>? statuses,
}) {
  if (userId == null || !onlineUserIds.contains(userId)) {
    return null;
  }
  return statuses?[userId] ?? PresenceStatus.online;
}

abstract interface class PresenceRepository {
  /// The current user's saved status and show-online switch.
  Future<PresenceSettings> loadSettings();

  Future<void> setStatus(PresenceStatus status);

  Future<void> setShowOnlineStatus(bool show);

  /// Streams which of the people the current user may see are online, with
  /// their status. The current user is counted as here with [ownStatus], and
  /// again whenever it changes; null leaves them watching only, so others
  /// see them offline.
  Stream<Map<String, PresenceStatus>> statuses(
    ValueListenable<PresenceStatus?> ownStatus,
  );
}

abstract interface class PresenceDataSource {
  /// The user's `user_privacy_settings` row, or null when they never saved
  /// one.
  Future<Map<String, dynamic>?> settings(String userId);

  Future<void> rpc(String functionName, Map<String, dynamic> params);

  /// The people [currentUserId] may see who are online, with their status,
  /// and [currentUserId] itself while [ownStatus] isn't null. Keeps the
  /// user counted as here, too.
  Stream<Map<String, PresenceStatus>> presence({
    required String currentUserId,
    required ValueListenable<PresenceStatus?> ownStatus,
  });
}

class SupabasePresenceRepository implements PresenceRepository {
  SupabasePresenceRepository(SupabaseClient client)
    : this.withDataSource(
        SupabasePresenceDataSource(client),
        currentUserId: () => client.auth.currentUser?.id,
      );

  const SupabasePresenceRepository.withDataSource(
    this._dataSource, {
    required this._currentUserId,
  });

  final PresenceDataSource _dataSource;
  final String? Function() _currentUserId;

  @override
  Future<PresenceSettings> loadSettings() async {
    final userId = _currentUserId();
    if (userId == null) {
      return const PresenceSettings();
    }
    return PresenceSettings.fromJson(await _dataSource.settings(userId));
  }

  @override
  Future<void> setStatus(PresenceStatus status) async {
    await _dataSource.rpc('set_presence_status', {'new_status': status.value});
  }

  @override
  Future<void> setShowOnlineStatus(bool show) async {
    await _dataSource.rpc('set_show_online_status', {'show': show});
  }

  @override
  Stream<Map<String, PresenceStatus>> statuses(
    ValueListenable<PresenceStatus?> ownStatus,
  ) {
    final userId = _currentUserId();
    if (userId == null) {
      return Stream.value(const <String, PresenceStatus>{});
    }
    return _dataSource.presence(currentUserId: userId, ownStatus: ownStatus);
  }
}

class SupabasePresenceDataSource implements PresenceDataSource {
  const SupabasePresenceDataSource(this._client, {this.visible});

  /// How often a visible client tells the server it is here.
  static const heartbeatInterval = Duration(minutes: 2);

  final SupabaseClient _client;

  /// Whether the app can be seen; the heartbeat only runs while it can
  /// (see [PresenceHeartbeat]). The app's own lifecycle when null.
  final ValueListenable<bool>? visible;

  @override
  Future<Map<String, dynamic>?> settings(String userId) {
    return _client
        .from('user_privacy_settings')
        .select('presence_status,show_online_status')
        .eq('user_id', userId)
        .maybeSingle();
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    await _client.rpc(functionName, params: params);
  }

  @override
  Stream<Map<String, PresenceStatus>> presence({
    required String currentUserId,
    required ValueListenable<PresenceStatus?> ownStatus,
  }) {
    RealtimeChannel? channel;
    late StreamController<PresenceSignal> signals;

    // Counts the user as here for the server (who sees them, @here, circle
    // discovery). [shown] is what the client shows for itself; the server
    // only takes "idle" from it. A server from before 202610190070 does not
    // know the second argument: fall back to the first alone.
    void beat(bool online, PresenceStatus? shown) {
      unawaited(() async {
        try {
          await _client.rpc<void>(
            'touch_presence',
            params: {'is_online': online, 'shown_status': ?shown?.value},
          );
        } on Object {
          try {
            await _client.rpc<void>(
              'touch_presence',
              params: {'is_online': online},
            );
          } on Object {
            // Offline; the next beat tells it.
          }
        }
      }());
    }

    Future<Map<String, PresenceStatus>> fetch(List<String>? ids) async {
      final rows = await _client.rpc<dynamic>(
        'visible_presence',
        params: {'target_ids': ids},
      );
      return presenceFromRows(rows);
    }

    signals = StreamController<PresenceSignal>(
      onListen: () {
        // A private channel of the user's own: the database tells only them,
        // and only about people they may see.
        final live = _client.channel(
          presenceUpdatesTopic(currentUserId),
          opts: privateChannelConfig(),
        );
        channel = live;
        for (final event in const ['changed', 'reset']) {
          live.onBroadcast(
            event: event,
            callback: (message) =>
                signals.add(presenceSignalFromBroadcast(event, message)),
          );
        }
        live.subscribe((status, error) {
          // Anything may have changed while the line was down.
          if (status == RealtimeSubscribeStatus.subscribed) {
            signals.add(const PresenceSignal.reset());
          }
        });
      },
      onCancel: () async {
        final live = channel;
        if (live != null) {
          await _client.removeChannel(live);
        }
      },
    );

    return PresenceFeed(
      currentUserId: currentUserId,
      ownStatus: ownStatus,
      fetch: fetch,
      signals: signals.stream,
      beat: beat,
      visible: visible ?? AppVisibility.instance.visible,
      heartbeatInterval: heartbeatInterval,
    ).stream;
  }
}

class UninitializedPresenceRepository implements PresenceRepository {
  const UninitializedPresenceRepository();

  @override
  Future<PresenceSettings> loadSettings() {
    throw StateError('Supabase must be initialized before loading presence.');
  }

  @override
  Future<void> setStatus(PresenceStatus status) {
    throw StateError('Supabase must be initialized before setting a status.');
  }

  @override
  Future<void> setShowOnlineStatus(bool show) {
    throw StateError('Supabase must be initialized before saving privacy.');
  }

  @override
  Stream<Map<String, PresenceStatus>> statuses(
    ValueListenable<PresenceStatus?> ownStatus,
  ) => const Stream<Map<String, PresenceStatus>>.empty();
}
