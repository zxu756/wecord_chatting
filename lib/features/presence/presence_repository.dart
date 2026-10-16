import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/presence_status.dart';

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

/// Everyone who has the app open right now, anywhere in it, with their
/// status. The shell keeps this joined for as long as someone is signed in
/// (see [PresenceRepository.statuses]); everything else just reads it.
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
      return ref.watch(presenceRepositoryProvider).statuses(ownStatus);
    });

/// Ids of users who have the app open right now (see
/// [presenceStatusesProvider]).
final onlineUserIdsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final statuses = ref.watch(presenceStatusesProvider).value;
  return statuses == null
      ? const Stream<Set<String>>.empty()
      : Stream.value(statuses.keys.toSet());
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

  /// Joins the app-wide presence channel and streams who is online with
  /// their status. The current user is announced with [ownStatus], and
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

  /// Everyone tracked on the app-wide presence channel, with their status.
  /// Tracks [currentUserId] with [ownStatus] while it isn't null.
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
  const SupabasePresenceDataSource(this._client);

  static const channelName = 'online-users';

  /// How often a visible, online client tells the server it is here.
  static const heartbeatInterval = Duration(minutes: 2);

  final SupabaseClient _client;

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
    late RealtimeChannel channel;
    late StreamController<Map<String, PresenceStatus>> controller;
    var subscribed = false;
    var tracking = false;
    Timer? heartbeat;

    // Discovery counts members online from these heartbeats (see
    // touch_presence); older servers without it just fail quietly.
    void beat(bool online) {
      unawaited(
        _client
            .rpc<void>('touch_presence', params: {'is_online': online})
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }

    void stopBeating() {
      if (heartbeat != null) {
        heartbeat?.cancel();
        heartbeat = null;
        beat(false);
      }
    }

    void emit() {
      if (controller.isClosed) {
        return;
      }
      controller.add(presenceStatusesFromState(channel.presenceState()));
    }

    // Announces the current status, or stops announcing; only once the
    // channel is up.
    void sync() {
      if (!subscribed) {
        return;
      }
      final status = ownStatus.value;
      if (status == null) {
        if (tracking) {
          tracking = false;
          unawaited(channel.untrack());
        }
        stopBeating();
        return;
      }
      tracking = true;
      if (heartbeat == null) {
        beat(true);
        heartbeat = Timer.periodic(heartbeatInterval, (_) => beat(true));
      }
      unawaited(
        channel.track({
          'user_id': currentUserId,
          'status': status.value,
          'online_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    }

    controller = StreamController<Map<String, PresenceStatus>>(
      onListen: () {
        // Until the first sync, only the current user is known to be here.
        controller.add({currentUserId: ?ownStatus.value});
        ownStatus.addListener(sync);
        channel = _client
            .channel(
              channelName,
              opts: RealtimeChannelConfig(key: currentUserId),
            )
            .onPresenceSync((payload) => emit())
            .onPresenceJoin((payload) => emit())
            .onPresenceLeave((payload) => emit())
            .subscribe((status, error) {
              if (status == RealtimeSubscribeStatus.subscribed) {
                subscribed = true;
                sync();
              }
            });
      },
      onCancel: () async {
        ownStatus.removeListener(sync);
        stopBeating();
        if (tracking) {
          await channel.untrack();
        }
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }
}

/// Each presence key's status. Someone with the app open in several places
/// shows the most present one: Online, then Do Not Disturb, then Idle.
Map<String, PresenceStatus> presenceStatusesFromState(
  List<SinglePresenceState> state,
) {
  const rank = [
    PresenceStatus.online,
    PresenceStatus.doNotDisturb,
    PresenceStatus.idle,
  ];
  final statuses = <String, PresenceStatus>{};
  for (final entry in state) {
    // Older clients track no status, which reads as online.
    final shown = [
      for (final presence in entry.presences)
        PresenceStatus.fromJson(presence.payload['status']),
    ].where(rank.contains);
    if (entry.presences.isEmpty) {
      statuses[entry.key] = PresenceStatus.online;
    } else if (shown.isNotEmpty) {
      statuses[entry.key] = shown.reduce(
        (best, status) =>
            rank.indexOf(status) < rank.indexOf(best) ? status : best,
      );
    }
  }
  return statuses;
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
