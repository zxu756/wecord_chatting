import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wecord/features/presence/presence_heartbeat.dart';
import 'package:wecord/shared/models/presence_status.dart';

/// What the database tells a viewer on `presence-updates:<viewer id>`
/// (supabase/migrations/202610190070_presence_visibility.sql): these people
/// came, went or changed (read them again), or everything may have changed.
/// It never carries a status.
class PresenceSignal {
  const PresenceSignal.changed(this.userIds) : reset = false;

  const PresenceSignal.reset() : userIds = const [], reset = true;

  /// Whose presence to read again.
  final List<String> userIds;

  /// Read everybody again (the channel just joined, or the viewer's own
  /// circles and chats changed).
  final bool reset;
}

/// The online status of the people the signed-in user may see.
///
/// The server decides who that is (friends, circle and chat mates, nobody
/// blocked, nobody who hides) and answers [fetch]; the channel behind
/// [signals] only says whom to ask about. So a status change shows up after
/// [batchDelay] plus one request, and a missed signal, an expired client or
/// a changed relationship is healed by the full read every [refreshInterval]
/// and whenever the app can be seen again.
///
/// The feed also keeps the current user counted as here: it beats
/// (`touch_presence`) while the app can be seen, and again whenever the
/// user's own status changes.
class PresenceFeed {
  PresenceFeed({
    required this.currentUserId,
    required this.ownStatus,
    required this.fetch,
    required this.signals,
    required this.beat,
    required this.visible,
    this.batchDelay = const Duration(milliseconds: 500),
    this.refreshInterval = const Duration(minutes: 1),
    this.heartbeatInterval = const Duration(minutes: 2),
  });

  /// Matches the server's limit on ids in one read.
  static const maxIdsPerRead = 200;

  final String currentUserId;

  /// How the current user shows to others; null while hidden.
  final ValueListenable<PresenceStatus?> ownStatus;

  /// Everyone the user may see who is online ([ids] null), or just [ids].
  final Future<Map<String, PresenceStatus>> Function(List<String>? ids) fetch;

  final Stream<PresenceSignal> signals;

  /// Sends `touch_presence(online, shown)`.
  final void Function(bool online, PresenceStatus? shown) beat;

  /// Whether the app can be seen.
  final ValueListenable<bool> visible;

  /// How long ids from signals are collected before one read.
  final Duration batchDelay;
  final Duration refreshInterval;
  final Duration heartbeatInterval;

  late final StreamController<Map<String, PresenceStatus>> _controller =
      StreamController<Map<String, PresenceStatus>>(
        onListen: _start,
        onCancel: _stop,
      );

  PresenceHeartbeat? _heartbeat;
  StreamSubscription<PresenceSignal>? _signals;
  Timer? _refresh;
  Timer? _batch;
  var _others = const <String, PresenceStatus>{};
  var _readAll = false;
  final _readIds = <String>{};
  var _reading = false;
  var _stopped = false;

  /// The people the user may see, plus the user themselves while shown.
  Stream<Map<String, PresenceStatus>> get stream => _controller.stream;

  void _start() {
    _stopped = false;
    // Until the first read, only the current user is known to be here.
    _emit();
    ownStatus.addListener(_ownChanged);
    visible.addListener(_visibleChanged);
    _signals = signals.listen(_onSignal);
    _heartbeat = PresenceHeartbeat(
      beat: (online) => beat(online, online ? ownStatus.value : null),
      visible: visible,
      interval: heartbeatInterval,
    )..wanted = true;
    _refresh = Timer.periodic(refreshInterval, (_) => _request(all: true));
    _request(all: true);
  }

  Future<void> _stop() async {
    _stopped = true;
    ownStatus.removeListener(_ownChanged);
    visible.removeListener(_visibleChanged);
    _refresh?.cancel();
    _batch?.cancel();
    _heartbeat?.dispose();
    _heartbeat = null;
    await _signals?.cancel();
    _signals = null;
    _others = const {};
    _readAll = false;
    _readIds.clear();
  }

  void _ownChanged() {
    _emit();
    // The server needs to know when the user shows again after being hidden,
    // or goes idle (away from the keyboard).
    if (_heartbeat?.beating ?? false) {
      beat(true, ownStatus.value);
    }
  }

  void _visibleChanged() {
    if (visible.value) {
      // Whatever happened while nobody looked.
      _request(all: true);
    }
  }

  void _onSignal(PresenceSignal signal) {
    if (signal.reset) {
      _request(all: true);
    } else {
      _request(ids: signal.userIds);
    }
  }

  void _emit() {
    if (_controller.isClosed || _stopped) {
      return;
    }
    final own = ownStatus.value;
    _controller.add({..._others, currentUserId: ?own});
  }

  void _request({bool all = false, List<String> ids = const []}) {
    if (_stopped) {
      return;
    }
    if (!visible.value) {
      // Nobody is looking; the read happens when the app is seen again.
      return;
    }
    if (all) {
      _readAll = true;
      _batch?.cancel();
      _batch = null;
      unawaited(_flush());
      return;
    }
    _readIds.addAll(ids.where((id) => id != currentUserId));
    if (_readIds.isEmpty) {
      return;
    }
    if (_readIds.length > maxIdsPerRead) {
      _readAll = true;
      _readIds.clear();
    }
    _batch ??= Timer(batchDelay, () {
      _batch = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (_reading) {
      // The running read picks up what was asked meanwhile.
      return;
    }
    _reading = true;
    try {
      while (!_stopped && (_readAll || _readIds.isNotEmpty)) {
        final all = _readAll;
        final ids = [..._readIds];
        _readAll = false;
        _readIds.clear();
        try {
          final read = await fetch(all ? null : ids);
          if (_stopped) {
            return;
          }
          _others = all
              ? {...read}
              : {
                  for (final entry in _others.entries)
                    if (!ids.contains(entry.key)) entry.key: entry.value,
                  ...read,
                };
          _others = Map.of(_others)..remove(currentUserId);
          _emit();
        } on Object {
          // Offline, or a server without the function: keep what is shown
          // and try again at the next signal or refresh.
        }
      }
    } finally {
      _reading = false;
    }
  }
}

/// One row of `visible_presence()`: the user and the status others see.
Map<String, PresenceStatus> presenceFromRows(Object? rows) {
  final statuses = <String, PresenceStatus>{};
  if (rows is! List) {
    return statuses;
  }
  for (final row in rows) {
    if (row is! Map) {
      continue;
    }
    final id = row['user_id'];
    if (id is! String) {
      continue;
    }
    final status = PresenceStatus.fromJson(row['status']);
    // The server never sends Invisible; if it ever did, it would mean offline.
    if (status != PresenceStatus.invisible) {
      statuses[id] = status;
    }
  }
  return statuses;
}

/// The signal a broadcast message on `presence-updates:<id>` carries.
PresenceSignal presenceSignalFromBroadcast(String event, Object? message) {
  if (event == 'reset') {
    return const PresenceSignal.reset();
  }
  final inner = message is Map ? message['payload'] : null;
  final ids = inner is Map ? inner['user_ids'] : null;
  return PresenceSignal.changed([
    if (ids is List)
      for (final id in ids)
        if (id is String) id,
  ]);
}
