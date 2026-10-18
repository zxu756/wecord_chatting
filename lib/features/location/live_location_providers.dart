import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_repository.dart';
import 'package:wecord/shared/app_visibility.dart';

/// How often the list of shares is checked again with the server while a
/// chat is open: someone blocked, a card taken down or a share ended without
/// a message all show up here at the latest. The check rests while the app
/// is hidden and runs at once when it can be seen again.
const liveSharesRefresh = Duration(seconds: 45);

/// The shares running in a chat that this person may see, kept up to date:
/// the list changes when someone starts or stops, and drops a share the
/// moment its time is up.
final liveSharesProvider = StreamProvider.autoDispose
    .family<List<LiveShare>, String>((ref, conversationId) {
      final repository = ref.watch(locationRepositoryProvider);
      final controller = StreamController<List<LiveShare>>();
      List<LiveShare> loaded = const [];
      List<LiveShare>? emitted;
      Timer? expiry;
      Timer? poll;
      Timer? debounce;
      var closed = false;

      void emit() {
        if (closed) {
          return;
        }
        final now = clock.now().toUtc();
        final running = [
          for (final share in loaded)
            if (share.isRunningAt(now)) share,
        ];
        if (emitted == null || !listEquals(emitted, running)) {
          emitted = running;
          controller.add(running);
        }
        expiry?.cancel();
        if (running.isNotEmpty) {
          final soonest = running
              .map((share) => share.endsAt)
              .reduce((a, b) => a.isBefore(b) ? a : b);
          expiry = Timer(
            soonest.difference(now) + const Duration(milliseconds: 50),
            emit,
          );
        }
      }

      Future<void> load() async {
        try {
          loaded = await repository.listShares(conversationId);
          emit();
        } on Object catch (error, stackTrace) {
          if (!closed && emitted == null) {
            controller.addError(error, stackTrace);
          }
        }
      }

      final visible = ref.watch(appVisibleProvider);

      void startPolling() {
        poll?.cancel();
        poll = Timer.periodic(liveSharesRefresh, (_) => unawaited(load()));
      }

      // Nobody is looking while the app is hidden: no polling then. A share
      // still ends on time (the expiry timer is not paused, and the list is
      // worked out again with the clock when the app is back) and anything
      // missed is read at once.
      var wasVisible = visible.value;
      void visibilityChanged() {
        final nowVisible = visible.value;
        if (nowVisible == wasVisible) {
          return;
        }
        wasVisible = nowVisible;
        if (nowVisible) {
          emit();
          unawaited(load());
          startPolling();
        } else {
          poll?.cancel();
          poll = null;
        }
      }

      unawaited(load());
      if (wasVisible) {
        startPolling();
      }
      visible.addListener(visibilityChanged);
      final changes = repository.sharesChanged(conversationId).listen((_) {
        debounce?.cancel();
        debounce = Timer(
          const Duration(milliseconds: 300),
          () => unawaited(load()),
        );
      }, onError: (Object _) {});

      ref.onDispose(() {
        closed = true;
        visible.removeListener(visibilityChanged);
        expiry?.cancel();
        poll?.cancel();
        debounce?.cancel();
        unawaited(changes.cancel());
        unawaited(controller.close());
      });
      return controller.stream;
    });

/// The latest position of each person sharing in a chat, by person.
class LivePositions {
  const LivePositions({this.latest = const {}, this.unavailable = const {}});

  /// By user id.
  final Map<String, LivePosition> latest;

  /// People whose share could not be listened to (the server refused the
  /// channel).
  final Set<String> unavailable;

  LivePositions copyWith({
    Map<String, LivePosition>? latest,
    Set<String>? unavailable,
  }) {
    return LivePositions(
      latest: latest ?? this.latest,
      unavailable: unavailable ?? this.unavailable,
    );
  }
}

/// Listens to everyone sharing in a chat (but this person: their own
/// position is on the device) while the map is open, and holds the latest
/// position of each. Positions are only ever kept here, in memory.
class LivePositionsController extends Notifier<LivePositions> {
  LivePositionsController(this._conversationId);

  final String _conversationId;
  final _channels = <String, LivePositionChannel>{};
  final _subscriptions = <String, List<StreamSubscription<Object?>>>{};
  final _userByShare = <String, String>{};

  @override
  LivePositions build() {
    ref.onDispose(() {
      for (final subscriptions in _subscriptions.values) {
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
      }
      _subscriptions.clear();
      for (final channel in _channels.values) {
        unawaited(channel.close());
      }
      _channels.clear();
    });
    ref.listen<AsyncValue<List<LiveShare>>>(
      liveSharesProvider(_conversationId),
      (previous, next) => _sync(next.value ?? const []),
      fireImmediately: true,
    );
    return const LivePositions();
  }

  void _sync(List<LiveShare> shares) {
    final me = ref.read(locationUserIdProvider);
    final wanted = {
      for (final share in shares)
        if (share.userId != me) share.id: share,
    };
    for (final id in _channels.keys.toList()) {
      if (!wanted.containsKey(id)) {
        _close(id);
      }
    }
    for (final share in wanted.values) {
      if (!_channels.containsKey(share.id)) {
        _open(share);
      }
    }
  }

  void _open(LiveShare share) {
    final LivePositionChannel channel;
    try {
      channel = ref.read(locationRepositoryProvider).openChannel(share.id);
    } on Object {
      state = state.copyWith(unavailable: {...state.unavailable, share.userId});
      return;
    }
    _channels[share.id] = channel;
    _userByShare[share.id] = share.userId;
    _subscriptions[share.id] = [
      channel.positions.listen((position) {
        final latest = state.latest[share.userId];
        // Late arrivals do not move someone back.
        if (latest != null && latest.at.isAfter(position.at)) {
          return;
        }
        state = state.copyWith(
          latest: {...state.latest, share.userId: position},
          unavailable: {...state.unavailable}..remove(share.userId),
        );
      }),
      channel.joined.listen((joined) {
        if (joined) {
          state = state.copyWith(
            unavailable: {...state.unavailable}..remove(share.userId),
          );
          // Ask for where they are now instead of waiting for the next tick.
          unawaited(channel.requestLatest());
        } else {
          state = state.copyWith(
            unavailable: {...state.unavailable, share.userId},
          );
        }
      }),
    ];
  }

  void _close(String shareId) {
    final userId = _userByShare.remove(shareId);
    for (final subscription in _subscriptions.remove(shareId) ?? const []) {
      unawaited(subscription.cancel());
    }
    final channel = _channels.remove(shareId);
    if (channel != null) {
      unawaited(channel.close());
    }
    if (userId != null) {
      state = LivePositions(
        latest: {...state.latest}..remove(userId),
        unavailable: {...state.unavailable}..remove(userId),
      );
    }
  }
}

final livePositionsProvider = NotifierProvider.autoDispose
    .family<LivePositionsController, LivePositions, String>(
      LivePositionsController.new,
    );
