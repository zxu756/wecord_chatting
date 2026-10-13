import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) {
  try {
    return SupabasePresenceRepository(ref.watch(supabaseClientProvider));
  } on AssertionError {
    return const UninitializedPresenceRepository();
  }
});

/// Ids of users who have the app open right now, anywhere in it. The shell
/// keeps this joined for as long as someone is signed in (see
/// [PresenceRepository.onlineUserIds]); everything else just reads it.
final onlineUserIdsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final userId = ref.watch(
    authStateProvider.select((state) => state.valueOrNull?.id),
  );
  if (userId == null) {
    return Stream<Set<String>>.value(const <String>{});
  }
  return ref.watch(presenceRepositoryProvider).onlineUserIds();
});

abstract interface class PresenceRepository {
  /// Joins the app-wide presence channel and streams who is online. The
  /// current user is announced too, unless they turned off
  /// `show_online_status`; then they only watch, and others see them as
  /// offline (so do they themselves).
  Stream<Set<String>> onlineUserIds();
}

abstract interface class PresenceDataSource {
  /// The user's `show_online_status` privacy setting, or null when they
  /// never saved privacy settings.
  Future<bool?> showOnlineStatus(String userId);

  /// Keys of everyone tracked on the app-wide presence channel. Tracks
  /// [currentUserId] when [trackSelf] is true.
  Stream<Set<String>> presence({
    required String currentUserId,
    required bool trackSelf,
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
    required String? Function() currentUserId,
  }) : _currentUserId = currentUserId;

  final PresenceDataSource _dataSource;
  final String? Function() _currentUserId;

  @override
  Stream<Set<String>> onlineUserIds() async* {
    final userId = _currentUserId();
    if (userId == null) {
      yield const <String>{};
      return;
    }
    var showOnlineStatus = true;
    try {
      showOnlineStatus = await _dataSource.showOnlineStatus(userId) ?? true;
    } catch (_) {
      // Fall back to the default (visible) when the setting can't be read.
    }
    yield* _dataSource.presence(
      currentUserId: userId,
      trackSelf: showOnlineStatus,
    );
  }
}

class SupabasePresenceDataSource implements PresenceDataSource {
  const SupabasePresenceDataSource(this._client);

  static const channelName = 'online-users';

  final SupabaseClient _client;

  @override
  Future<bool?> showOnlineStatus(String userId) async {
    final row = await _client
        .from('user_privacy_settings')
        .select('show_online_status')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['show_online_status'] as bool?;
  }

  @override
  Stream<Set<String>> presence({
    required String currentUserId,
    required bool trackSelf,
  }) {
    late RealtimeChannel channel;
    late StreamController<Set<String>> controller;

    void emit() {
      if (controller.isClosed) {
        return;
      }
      controller.add({for (final state in channel.presenceState()) state.key});
    }

    controller = StreamController<Set<String>>(
      onListen: () {
        // Until the first sync, only the current user is known to be here.
        controller.add({if (trackSelf) currentUserId});
        channel = _client
            .channel(
              channelName,
              opts: RealtimeChannelConfig(key: currentUserId),
            )
            .onPresenceSync((payload) => emit())
            .onPresenceJoin((payload) => emit())
            .onPresenceLeave((payload) => emit())
            .subscribe((status, error) {
              if (trackSelf && status == RealtimeSubscribeStatus.subscribed) {
                unawaited(
                  channel.track({
                    'user_id': currentUserId,
                    'online_at': DateTime.now().toUtc().toIso8601String(),
                  }),
                );
              }
            });
      },
      onCancel: () async {
        if (trackSelf) {
          await channel.untrack();
        }
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }
}

class UninitializedPresenceRepository implements PresenceRepository {
  const UninitializedPresenceRepository();

  @override
  Stream<Set<String>> onlineUserIds() => const Stream<Set<String>>.empty();
}
