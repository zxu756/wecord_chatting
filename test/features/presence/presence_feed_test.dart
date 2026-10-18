import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/presence/presence_feed.dart';
import 'package:wecord/shared/models/presence_status.dart';

/// The server side of the feed, scripted: what visible_presence answers, and
/// the signals the database would send.
class _Server {
  var visible = <String, PresenceStatus>{};
  final reads = <List<String>?>[];
  final beats = <(bool, PresenceStatus?)>[];
  final signals = StreamController<PresenceSignal>.broadcast();
  var failing = false;
  var signalListeners = 0;

  Future<Map<String, PresenceStatus>> fetch(List<String>? ids) async {
    reads.add(ids);
    if (failing) {
      throw StateError('offline');
    }
    if (ids == null) {
      return {...visible};
    }
    return {
      for (final entry in visible.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    };
  }

  Stream<PresenceSignal> get signalStream => Stream.multi((controller) {
    signalListeners++;
    final subscription = signals.stream.listen(controller.add);
    controller.onCancel = () {
      signalListeners--;
      return subscription.cancel();
    };
  });
}

({
  PresenceFeed feed,
  _Server server,
  ValueNotifier<PresenceStatus?> own,
  ValueNotifier<bool> visible,
  List<Map<String, PresenceStatus>> emitted,
  StreamSubscription<Map<String, PresenceStatus>> subscription,
})
_open({
  PresenceStatus? own = PresenceStatus.online,
  Map<String, PresenceStatus> visible = const {},
}) {
  final server = _Server()..visible = {...visible};
  final ownStatus = ValueNotifier<PresenceStatus?>(own);
  final appVisible = ValueNotifier<bool>(true);
  final feed = PresenceFeed(
    currentUserId: 'me',
    ownStatus: ownStatus,
    fetch: server.fetch,
    signals: server.signalStream,
    beat: (online, shown) => server.beats.add((online, shown)),
    visible: appVisible,
  );
  final emitted = <Map<String, PresenceStatus>>[];
  final subscription = feed.stream.listen(emitted.add);
  return (
    feed: feed,
    server: server,
    own: ownStatus,
    visible: appVisible,
    emitted: emitted,
    subscription: subscription,
  );
}

void main() {
  test(
    'starts with the user alone, then shows who the server lets them see',
    () {
      fakeAsync((async) {
        final open = _open(
          visible: {'ann': PresenceStatus.online, 'bo': PresenceStatus.idle},
        );

        async.flushMicrotasks();
        expect(open.emitted.first, {'me': PresenceStatus.online});

        expect(open.server.reads, [null]);
        expect(open.emitted.last, {
          'me': PresenceStatus.online,
          'ann': PresenceStatus.online,
          'bo': PresenceStatus.idle,
        });
        open.subscription.cancel();
      });
    },
  );

  test('a signal reads just those people, after a short wait', () {
    fakeAsync((async) {
      final open = _open(visible: {'ann': PresenceStatus.online});
      async.flushMicrotasks();
      open.server.reads.clear();

      open.server.visible = {
        'ann': PresenceStatus.doNotDisturb,
        'bo': PresenceStatus.online,
      };
      open.server.signals.add(const PresenceSignal.changed(['ann']));
      async.elapse(const Duration(milliseconds: 100));
      expect(open.server.reads, isEmpty);

      async.elapse(const Duration(milliseconds: 500));
      expect(open.server.reads, [
        ['ann'],
      ]);
      // Bo was not asked about, so is not shown yet.
      expect(open.emitted.last, {
        'me': PresenceStatus.online,
        'ann': PresenceStatus.doNotDisturb,
      });
      open.subscription.cancel();
    });
  });

  test('signals close together are read in one request', () {
    fakeAsync((async) {
      final open = _open();
      async.flushMicrotasks();
      open.server.reads.clear();
      open.server.visible = {
        'ann': PresenceStatus.online,
        'bo': PresenceStatus.online,
      };

      open.server.signals
        ..add(const PresenceSignal.changed(['ann']))
        ..add(const PresenceSignal.changed(['bo', 'ann']))
        ..add(const PresenceSignal.changed(['me']));
      async.elapse(const Duration(seconds: 1));

      expect(open.server.reads, hasLength(1));
      expect(open.server.reads.single!.toSet(), {'ann', 'bo'});
      expect(open.emitted.last.keys.toSet(), {'me', 'ann', 'bo'});
      open.subscription.cancel();
    });
  });

  test('someone the server no longer returns disappears', () {
    fakeAsync((async) {
      final open = _open(
        visible: {'ann': PresenceStatus.online, 'bo': PresenceStatus.online},
      );
      async.flushMicrotasks();

      // Ann went offline, or blocked the user, or hid.
      open.server.visible = {'bo': PresenceStatus.online};
      open.server.signals.add(const PresenceSignal.changed(['ann']));
      async.elapse(const Duration(seconds: 1));

      expect(open.emitted.last, {
        'me': PresenceStatus.online,
        'bo': PresenceStatus.online,
      });
      open.subscription.cancel();
    });
  });

  test('a reset reads everybody at once and replaces the list', () {
    fakeAsync((async) {
      final open = _open(visible: {'ann': PresenceStatus.online});
      async.flushMicrotasks();
      open.server.reads.clear();

      // The user left the circle they shared with Ann.
      open.server.visible = {'cy': PresenceStatus.idle};
      open.server.signals.add(const PresenceSignal.reset());
      async.flushMicrotasks();

      expect(open.server.reads, [null]);
      expect(open.emitted.last, {
        'me': PresenceStatus.online,
        'cy': PresenceStatus.idle,
      });
      open.subscription.cancel();
    });
  });

  test('everything is read again every minute', () {
    fakeAsync((async) {
      final open = _open();
      async.flushMicrotasks();
      open.server.reads.clear();
      open.server.visible = {'ann': PresenceStatus.online};

      async.elapse(const Duration(seconds: 59));
      expect(open.server.reads, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(open.server.reads, [null]);
      expect(open.emitted.last.containsKey('ann'), isTrue);

      // So someone who vanished without saying goodbye drops out.
      open.server.visible = {};
      async.elapse(const Duration(minutes: 1));
      expect(open.emitted.last, {'me': PresenceStatus.online});
      open.subscription.cancel();
    });
  });

  test('a failed read keeps what is shown and recovers', () {
    fakeAsync((async) {
      final open = _open(visible: {'ann': PresenceStatus.online});
      async.flushMicrotasks();

      open.server.failing = true;
      open.server.signals.add(const PresenceSignal.reset());
      async.flushMicrotasks();
      expect(open.emitted.last.containsKey('ann'), isTrue);

      open.server.failing = false;
      open.server.visible = {'bo': PresenceStatus.online};
      async.elapse(const Duration(minutes: 1));
      expect(open.emitted.last, {
        'me': PresenceStatus.online,
        'bo': PresenceStatus.online,
      });
      open.subscription.cancel();
    });
  });

  test('a long list of ids becomes one full read', () {
    fakeAsync((async) {
      final open = _open();
      async.flushMicrotasks();
      open.server.reads.clear();

      open.server.signals.add(
        PresenceSignal.changed([for (var i = 0; i < 250; i++) 'user-$i']),
      );
      async.elapse(const Duration(seconds: 1));

      expect(open.server.reads, [null]);
      open.subscription.cancel();
    });
  });

  test('the user is counted as here, and the server hears of changes', () {
    fakeAsync((async) {
      final open = _open();
      async.flushMicrotasks();
      expect(open.server.beats, [(true, PresenceStatus.online)]);

      // Away from the keyboard.
      open.own.value = PresenceStatus.idle;
      async.flushMicrotasks();
      expect(open.server.beats.last, (true, PresenceStatus.idle));
      expect(open.emitted.last['me'], PresenceStatus.idle);

      // Hidden: still beats (to keep watching), without a status, and is not
      // in their own list.
      open.own.value = null;
      async.flushMicrotasks();
      expect(open.server.beats.last, (true, null));
      expect(open.emitted.last.containsKey('me'), isFalse);

      async.elapse(const Duration(minutes: 2));
      expect(open.server.beats.last, (true, null));

      open.subscription.cancel();
      async.flushMicrotasks();
      expect(open.server.beats.last, (false, null));
    });
  });

  test('nothing is read or sent while the app is hidden', () {
    fakeAsync((async) {
      final open = _open();
      async.flushMicrotasks();
      open.server.reads.clear();

      open.visible.value = false;
      expect(open.server.beats.last.$1, isFalse);

      open.server.signals.add(const PresenceSignal.changed(['ann']));
      async.elapse(const Duration(minutes: 5));
      expect(open.server.reads, isEmpty);

      // Back on screen: beats, and reads everything.
      open.server.visible = {'ann': PresenceStatus.online};
      open.visible.value = true;
      async.flushMicrotasks();
      expect(open.server.beats.last.$1, isTrue);
      expect(open.server.reads, [null]);
      expect(open.emitted.last.containsKey('ann'), isTrue);
      open.subscription.cancel();
    });
  });

  test('the user never appears twice, whatever the server says', () {
    fakeAsync((async) {
      final open = _open(
        own: PresenceStatus.doNotDisturb,
        visible: {'me': PresenceStatus.online, 'ann': PresenceStatus.online},
      );
      async.flushMicrotasks();

      expect(open.emitted.last['me'], PresenceStatus.doNotDisturb);
      open.subscription.cancel();
    });
  });

  test('cancelling stops listening for signals', () {
    fakeAsync((async) {
      final open = _open();
      async.flushMicrotasks();
      expect(open.server.signalListeners, 1);

      open.subscription.cancel();
      async.flushMicrotasks();
      expect(open.server.signalListeners, 0);

      open.server.reads.clear();
      async.elapse(const Duration(minutes: 3));
      expect(open.server.reads, isEmpty);
    });
  });

  group('wire formats', () {
    test('rows become statuses; unknown or hidden ones are left out', () {
      expect(
        presenceFromRows([
          {'user_id': 'a', 'status': 'online'},
          {'user_id': 'b', 'status': 'idle'},
          {'user_id': 'c', 'status': 'dnd'},
          {'user_id': 'd', 'status': 'invisible'},
          {'status': 'online'},
          'junk',
        ]),
        {
          'a': PresenceStatus.online,
          'b': PresenceStatus.idle,
          'c': PresenceStatus.doNotDisturb,
        },
      );
      expect(presenceFromRows(null), isEmpty);
      expect(presenceFromRows({'user_id': 'a'}), isEmpty);
    });

    test('broadcast messages become signals', () {
      final changed = presenceSignalFromBroadcast('changed', {
        'event': 'changed',
        'payload': {
          'id': 'x',
          'user_ids': ['a', 'b', 3],
        },
      });
      expect(changed.reset, isFalse);
      expect(changed.userIds, ['a', 'b']);

      expect(
        presenceSignalFromBroadcast('reset', {'payload': {}}).reset,
        isTrue,
      );
      expect(presenceSignalFromBroadcast('changed', null).userIds, isEmpty);
    });
  });
}
