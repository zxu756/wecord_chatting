import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_repository.dart';
import 'package:wecord/features/location/location_service.dart';

/// The signed-in person's id, to stop their sharing when it changes.
final locationUserIdProvider = Provider<String?>((ref) {
  try {
    final state = ref.watch(
      authStateProvider.select(
        (state) => (hasValue: state.hasValue, id: state.value?.id),
      ),
    );
    if (state.hasValue) {
      return state.id;
    }
    return ref.read(authRepositoryProvider).currentUser?.id;
  } on Object {
    return null;
  }
});

/// How often a position is repeated while the person stands still (so
/// others see the sharing is alive), and how long a reading may be old.
class LiveLocationTiming {
  const LiveLocationTiming({
    this.heartbeat = const Duration(seconds: 10),
    this.staleAfter = const Duration(seconds: 45),
  });

  final Duration heartbeat;

  /// After this long without a position, the map marks someone as paused.
  final Duration staleAfter;
}

final liveLocationTimingProvider = Provider<LiveLocationTiming>(
  (ref) => const LiveLocationTiming(),
);

/// Permission or services were not there when sharing was about to start.
class LocationNotAllowed implements Exception {
  const LocationNotAllowed(this.access);

  final LocationAccess access;

  @override
  String toString() => 'LocationNotAllowed($access)';
}

class LiveSharingState {
  const LiveSharingState({this.shares = const []});

  final List<OwnShare> shares;

  OwnShare? forConversation(String conversationId) {
    for (final share in shares) {
      if (share.conversationId == conversationId) {
        return share;
      }
    }
    return null;
  }

  bool get isSharing => shares.isNotEmpty;
}

/// Shares this device's position into chats, for as long as the person
/// chose.
///
/// While at least one share runs it follows the device's position and sends
/// it on each share's private channel as it changes and every few seconds
/// otherwise. It ends a share when its time is up, when the person stops it,
/// when they sign out or change account. Positions are never stored. The app
/// has no background location mode, so on iOS (and in a background browser
/// tab) sending pauses while WeCord is not in front, and carries on when it
/// is back.
class LiveLocationSharer extends Notifier<LiveSharingState> {
  final _channels = <String, LivePositionChannel>{};
  final _channelSubscriptions = <String, StreamSubscription<void>>{};
  final _expiry = <String, Timer>{};
  StreamSubscription<DevicePosition>? _positionSubscription;
  bool _streamPrecise = false;
  Timer? _heartbeat;
  DevicePosition? _lastReading;
  String? _userId;

  @override
  LiveSharingState build() {
    final userId = ref.watch(locationUserIdProvider);
    _userId = userId;
    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_sendLatest()),
    );
    ref.onDispose(() {
      lifecycle.dispose();
      _stopFollowing();
      for (final timer in _expiry.values) {
        timer.cancel();
      }
      _expiry.clear();
      for (final subscription in _channelSubscriptions.values) {
        unawaited(subscription.cancel());
      }
      _channelSubscriptions.clear();
      for (final channel in _channels.values) {
        unawaited(channel.close());
      }
      _channels.clear();
    });
    if (userId != null) {
      scheduleMicrotask(() => unawaited(_resume(userId)));
    }
    return const LiveSharingState();
  }

  bool get _alive => ref.mounted;

  /// Starts sharing in [conversationId] for [duration]. Asks for the
  /// location permission when it is needed; throws [LocationNotAllowed]
  /// when the person does not give it and [LocationRefused] when the server
  /// says no.
  Future<OwnShare> start({
    required String conversationId,
    required Duration duration,
    required bool precise,
  }) async {
    final service = ref.read(locationServiceProvider);
    final access = await service.requestAccess();
    if (access != LocationAccess.granted) {
      throw LocationNotAllowed(access);
    }
    final started = await ref
        .read(locationRepositoryProvider)
        .startShare(
          conversationId: conversationId,
          durationMinutes: duration.inMinutes,
          precise: precise,
        );
    final share = OwnShare(
      shareId: started.shareId,
      conversationId: conversationId,
      endsAt: started.endsAt,
      precise: precise,
    );
    if (_alive) {
      // Starting again in the same chat replaces the earlier share.
      final earlier = state.forConversation(conversationId);
      if (earlier != null) {
        await _forget(earlier.shareId);
      }
      _begin(share);
    }
    return share;
  }

  /// Stops sharing in [conversationId] (the person tapped Stop).
  Future<void> stop(String conversationId) async {
    final share = state.forConversation(conversationId);
    if (share == null) {
      return;
    }
    await _forget(share.shareId);
    try {
      await ref.read(locationRepositoryProvider).stopShare(share.shareId);
    } on Object {
      // The share ends at its time anyway, and nothing is sent any more.
    }
  }

  /// Stops everything (signing out).
  Future<void> stopAll() async {
    final all = [...state.shares];
    for (final share in all) {
      await _forget(share.shareId);
    }
    try {
      await ref.read(locationRepositoryProvider).stopAll();
    } on Object {
      // See [stop].
    }
  }

  /// Picks sharing up again after the app was restarted within a share's
  /// time, when the person still allows location.
  Future<void> _resume(String userId) async {
    try {
      final access = await ref.read(locationServiceProvider).access();
      final mine = await ref.read(locationRepositoryProvider).listMyShares();
      if (!_alive || _userId != userId || mine.isEmpty) {
        return;
      }
      if (access != LocationAccess.granted) {
        // Nothing can be sent: do not leave others believing it is.
        await ref.read(locationRepositoryProvider).stopAll();
        return;
      }
      for (final share in mine) {
        if (state.forConversation(share.conversationId) == null) {
          _begin(share);
        }
      }
    } on Object {
      // Offline or the server lacks the feature: nothing to resume.
    }
  }

  void _begin(OwnShare share) {
    final channel = ref
        .read(locationRepositoryProvider)
        .openChannel(share.shareId);
    _channels[share.shareId] = channel;
    // Someone just opened the map: answer with where we are at once.
    _channelSubscriptions[share.shareId] = channel.requests.listen(
      (_) => unawaited(_sendLatest()),
    );
    final remaining = share.remaining(clock.now());
    _expiry[share.shareId] = Timer(remaining, () {
      if (_alive) {
        unawaited(_forget(share.shareId));
      }
    });
    state = LiveSharingState(shares: [...state.shares, share]);
    _follow();
  }

  /// Ends the local side of a share.
  Future<void> _forget(String shareId) async {
    _expiry.remove(shareId)?.cancel();
    unawaited(_channelSubscriptions.remove(shareId)?.cancel());
    final channel = _channels.remove(shareId);
    if (_alive) {
      state = LiveSharingState(
        shares: [
          for (final share in state.shares)
            if (share.shareId != shareId) share,
        ],
      );
      if (state.shares.isEmpty) {
        _stopFollowing();
      } else {
        _follow();
      }
    }
    if (channel != null) {
      await channel.close();
    }
  }

  /// Follows the device while a share runs; exact readings when any share
  /// is precise.
  void _follow() {
    final precise = state.shares.any((share) => share.precise);
    if (_positionSubscription != null && _streamPrecise == precise) {
      return;
    }
    _stopFollowing();
    _streamPrecise = precise;
    final service = ref.read(locationServiceProvider);
    _positionSubscription = service
        .positions(precise: precise)
        .listen(
          (reading) {
            _lastReading = reading;
            unawaited(_sendLatest());
          },
          onError: (Object _) {
            // Permission taken away or no signal: keep the timers; the
            // map shows the sharing as paused until readings come again.
          },
        );
    final timing = ref.read(liveLocationTimingProvider);
    _heartbeat = Timer.periodic(
      timing.heartbeat,
      (_) => unawaited(_sendLatest()),
    );
    // A first reading without waiting for the person to move.
    unawaited(() async {
      try {
        final reading = await service.currentPosition(precise: precise);
        if (_alive && _positionSubscription != null) {
          _lastReading = reading;
          await _sendLatest();
        }
      } on Object {
        // The stream will deliver.
      }
    }());
  }

  void _stopFollowing() {
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _lastReading = null;
  }

  Future<void> _sendLatest() async {
    final reading = _lastReading;
    if (!_alive || reading == null || state.shares.isEmpty) {
      return;
    }
    final now = clock.now().toUtc();
    final updated = <OwnShare>[];
    for (final share in state.shares) {
      if (!share.endsAt.isAfter(now)) {
        updated.add(share);
        continue;
      }
      final point = share.precise ? reading.point : coarsen(reading.point);
      final position = LivePosition(
        point: point,
        at: now,
        accuracyMeters: share.precise ? reading.accuracyMeters : null,
        heading: share.precise ? reading.heading : null,
      );
      try {
        await _channels[share.shareId]?.send(position);
        updated.add(share.copyWith(lastPoint: point, lastSentAt: now));
      } on Object {
        updated.add(share);
      }
    }
    if (_alive) {
      // Keep the list as it is now (a share may have ended meanwhile).
      final byId = {for (final share in updated) share.shareId: share};
      state = LiveSharingState(
        shares: [
          for (final share in state.shares) byId[share.shareId] ?? share,
        ],
      );
    }
  }
}

final liveLocationSharerProvider =
    NotifierProvider<LiveLocationSharer, LiveSharingState>(
      LiveLocationSharer.new,
    );

/// Keeps the sharer alive while the signed-in app is up, so a share that was
/// running when the app was restarted carries on and ends on time.
class LiveLocationShellListener extends ConsumerWidget {
  const LiveLocationShellListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(liveLocationSharerProvider, (previous, next) {});
    return child;
  }
}
