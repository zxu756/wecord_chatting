import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device has a network connection at all. Always true unless
/// the app's bootstrap overrides it with [platformDeviceConnectivity]
/// (tests and platforms without the plugin stay online).
final deviceConnectivityProvider = StreamProvider<bool>(
  (ref) => Stream<bool>.value(true),
);

/// The device's connection from `connectivity_plus`: offline when every
/// interface reports none.
Stream<bool> platformDeviceConnectivity() async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  try {
    yield online(await connectivity.checkConnectivity());
  } catch (_) {
    yield true;
  }
  try {
    yield* connectivity.onConnectivityChanged.map(online).distinct();
  } catch (_) {
    // No plugin: assume online.
  }
}

/// How the realtime channels of open chats are doing.
enum RealtimeChannelState { joining, joined, failed }

/// Collects the state of every open realtime channel, so the app can tell
/// when the device is online but the server cannot be reached.
class RealtimeStatusTracker {
  final _states = <String, RealtimeChannelState>{};
  final _changes = StreamController<RealtimeHealth>.broadcast();

  RealtimeHealth get health => _healthOf(_states.values);

  Stream<RealtimeHealth> get changes => _changes.stream;

  void report(String channel, RealtimeChannelState state) {
    final before = health;
    _states[channel] = state;
    _emitIfChanged(before);
  }

  void forget(String channel) {
    final before = health;
    _states.remove(channel);
    _emitIfChanged(before);
  }

  void _emitIfChanged(RealtimeHealth before) {
    final after = health;
    if (after != before && !_changes.isClosed) {
      _changes.add(after);
    }
  }

  static RealtimeHealth _healthOf(Iterable<RealtimeChannelState> states) {
    if (states.any((state) => state == RealtimeChannelState.failed)) {
      return RealtimeHealth.failing;
    }
    return RealtimeHealth.healthy;
  }
}

enum RealtimeHealth { healthy, failing }

/// The app's realtime channels report here (see `SupabaseChatsDataSource`).
final realtimeStatusTracker = RealtimeStatusTracker();

final realtimeHealthProvider = StreamProvider<RealtimeHealth>((ref) async* {
  yield realtimeStatusTracker.health;
  yield* realtimeStatusTracker.changes;
});

/// What the connectivity banner says.
enum NetworkStatus {
  online,

  /// No network on the device: messages wait in the outbox.
  offline,

  /// The device is online but the server is not reached yet (just back
  /// online, or realtime keeps failing).
  reconnecting,
}

/// Combines the device's connection with the realtime channels: offline
/// when the device has no network, reconnecting while channels fail or
/// rejoin after coming back, online otherwise.
final networkStatusProvider = Provider<NetworkStatus>((ref) {
  final device = ref.watch(deviceConnectivityProvider).valueOrNull ?? true;
  if (!device) {
    return NetworkStatus.offline;
  }
  final realtime =
      ref.watch(realtimeHealthProvider).valueOrNull ?? RealtimeHealth.healthy;
  if (realtime == RealtimeHealth.failing) {
    return NetworkStatus.reconnecting;
  }
  return NetworkStatus.online;
});

/// Counts the times the device came back online, so data loaded while
/// offline can sync when it changes.
final reconnectCountProvider = Provider<int>((ref) {
  var count = 0;
  var wasOnline = true;
  ref.listen<bool>(
    deviceConnectivityProvider.select((value) => value.valueOrNull ?? true),
    (previous, online) {
      if (online && !wasOnline) {
        count++;
        ref.state = count;
      }
      wasOnline = online;
    },
    fireImmediately: true,
  );
  return count;
});
