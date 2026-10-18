import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/models/presence_status.dart';

void main() {
  test('loads the saved status and show-online switch', () async {
    final dataSource = FakePresenceDataSource()
      ..row = {'presence_status': 'dnd', 'show_online_status': false};
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final settings = await repository.loadSettings();

    expect(dataSource.settingsRequests, ['user-1']);
    expect(settings.status, PresenceStatus.doNotDisturb);
    expect(settings.showOnlineStatus, isFalse);
    expect(settings.hidden, isTrue);
  });

  test('missing settings default to online and shown', () async {
    final repository = SupabasePresenceRepository.withDataSource(
      FakePresenceDataSource(),
      currentUserId: () => 'user-1',
    );

    final settings = await repository.loadSettings();

    expect(settings, const PresenceSettings());
    expect(settings.hidden, isFalse);
  });

  test('saves the status and the switch through RPCs', () async {
    final dataSource = FakePresenceDataSource();
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.setStatus(PresenceStatus.invisible);
    await repository.setShowOnlineStatus(false);

    expect(dataSource.rpcs.map((call) => call.$1), [
      'set_presence_status',
      'set_show_online_status',
    ]);
    expect(dataSource.rpcs.first.$2, {'new_status': 'invisible'});
    expect(dataSource.rpcs.last.$2, {'show': false});
  });

  test('joins with the current user and their status', () async {
    final dataSource = FakePresenceDataSource();
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );
    final own = ValueNotifier<PresenceStatus?>(PresenceStatus.idle);

    final updates = <Map<String, PresenceStatus>>[];
    final subscription = repository.statuses(own).listen(updates.add);
    await pumpEventQueue();
    dataSource.updates.add({
      'user-1': PresenceStatus.idle,
      'user-2': PresenceStatus.doNotDisturb,
    });
    await pumpEventQueue();
    await subscription.cancel();

    expect(dataSource.joins.single.currentUserId, 'user-1');
    expect(dataSource.joins.single.ownStatus, same(own));
    expect(updates.single, {
      'user-1': PresenceStatus.idle,
      'user-2': PresenceStatus.doNotDisturb,
    });
    expect(dataSource.cancelled, isTrue);
  });

  test('signed out yields nobody and joins nothing', () async {
    final dataSource = FakePresenceDataSource();
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => null,
    );

    expect(await repository.statuses(ValueNotifier(null)).toList(), [
      <String, PresenceStatus>{},
    ]);
    expect(dataSource.joins, isEmpty);
    expect(await repository.loadSettings(), const PresenceSettings());
  });

  test('presenceOf needs someone online and defaults to Online', () {
    const online = {'a', 'b'};
    final statuses = {'a': PresenceStatus.idle};

    expect(
      presenceOf('a', onlineUserIds: online, statuses: statuses),
      PresenceStatus.idle,
    );
    expect(
      presenceOf('b', onlineUserIds: online, statuses: statuses),
      PresenceStatus.online,
    );
    expect(presenceOf('c', onlineUserIds: online, statuses: statuses), isNull);
    expect(presenceOf(null, onlineUserIds: online), isNull);
  });

  group('providers', () {
    late FakePresenceRepository presence;
    late StreamController<AuthUser?> authState;
    late ProviderContainer container;

    setUp(() {
      presence = FakePresenceRepository();
      authState = StreamController<AuthUser?>.broadcast();
      container = ProviderContainer(
        overrides: [
          presenceRepositoryProvider.overrideWithValue(presence),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
      );
      addTearDown(container.dispose);
    });

    test('onlineUserIdsProvider joins only while signed in', () async {
      final subscription = container.listen(
        onlineUserIdsProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);

      authState.add(null);
      await pumpEventQueue(times: 100);
      expect(container.read(onlineUserIdsProvider).value, <String>{});
      expect(presence.listens, 0);

      authState.add(const AuthUser(id: 'user-1'));
      await pumpEventQueue();
      presence.online.add({
        'user-1': PresenceStatus.online,
        'user-2': PresenceStatus.idle,
      });
      await pumpEventQueue(times: 100);
      expect(presence.listens, 1);
      expect(container.read(onlineUserIdsProvider).value, {'user-1', 'user-2'});
      expect(
        container.read(presenceStatusesProvider).value?['user-2'],
        PresenceStatus.idle,
      );
    });

    test('screens hear about who is online, not about repeated syncs or '
        'status changes', () async {
      var statusNotifications = 0;
      var onlineNotifications = 0;
      final statuses = container.listen(
        presenceStatusesProvider,
        (previous, next) => statusNotifications++,
      );
      final online = container.listen(
        onlineUserIdsProvider,
        (previous, next) => onlineNotifications++,
      );
      addTearDown(statuses.close);
      addTearDown(online.close);
      authState.add(const AuthUser(id: 'user-1'));
      await pumpEventQueue();

      final here = {
        'user-1': PresenceStatus.online,
        'user-2': PresenceStatus.online,
      };
      presence.online.add(here);
      await pumpEventQueue(times: 50);
      final afterFirst = (statusNotifications, onlineNotifications);

      // Every join, leave and re-announce is followed by a sync, most of
      // them with nothing new.
      for (var i = 0; i < 5; i++) {
        presence.online.add({...here});
        await pumpEventQueue(times: 50);
      }
      expect((statusNotifications, onlineNotifications), afterFirst);

      // Someone going Idle changes the statuses, not who is online.
      presence.online.add({...here, 'user-2': PresenceStatus.idle});
      await pumpEventQueue(times: 50);
      expect(statusNotifications, afterFirst.$1 + 1);
      expect(onlineNotifications, afterFirst.$2);
      expect(container.read(onlineUserIdsProvider).value, {'user-1', 'user-2'});

      // Someone leaving does.
      presence.online.add({'user-1': PresenceStatus.online});
      await pumpEventQueue(times: 50);
      expect(onlineNotifications, greaterThan(afterFirst.$2));
      expect(container.read(onlineUserIdsProvider).value, {'user-1'});
    });

    test('only the people the server lets the user see are online, '
        'and a blocked or hidden person drops out', () async {
      final subscription = container.listen(
        onlineUserIdsProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);
      authState.add(const AuthUser(id: 'user-1'));
      await pumpEventQueue();

      presence.online.add({
        'user-1': PresenceStatus.online,
        'friend': PresenceStatus.doNotDisturb,
        'circle-mate': PresenceStatus.idle,
      });
      await pumpEventQueue(times: 50);
      final statuses = container.read(presenceStatusesProvider).value!;
      final online = container.read(onlineUserIdsProvider).value!;
      expect(online, {'user-1', 'friend', 'circle-mate'});
      expect(
        presenceOf('friend', onlineUserIds: online, statuses: statuses),
        PresenceStatus.doNotDisturb,
      );
      // A stranger, a blocked user and someone hiding are simply not in the
      // list the server sends.
      expect(
        presenceOf('stranger', onlineUserIds: online, statuses: statuses),
        isNull,
      );

      // The friend blocks the user: the server stops sending them.
      presence.online.add({
        'user-1': PresenceStatus.online,
        'circle-mate': PresenceStatus.idle,
      });
      await pumpEventQueue(times: 50);
      expect(container.read(onlineUserIdsProvider).value, {
        'user-1',
        'circle-mate',
      });
    });

    test('signing out stops the feed and shows nobody', () async {
      final subscription = container.listen(
        onlineUserIdsProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);
      authState.add(const AuthUser(id: 'user-1'));
      await pumpEventQueue();
      presence.online.add({
        'user-1': PresenceStatus.online,
        'a': PresenceStatus.online,
      });
      await pumpEventQueue(times: 50);
      expect(container.read(onlineUserIdsProvider).value, {'user-1', 'a'});

      authState.add(null);
      await pumpEventQueue(times: 100);
      expect(container.read(onlineUserIdsProvider).value, <String>{});
    });

    test('the broadcast status follows the settings and idleness', () async {
      presence.settings = const PresenceSettings();
      final subscription = container.listen(
        presenceStatusesProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);
      authState.add(const AuthUser(id: 'user-1'));
      await pumpEventQueue();

      final own = presence.ownStatus!;
      expect(own.value, PresenceStatus.online);
      expect(container.read(ownPresenceProvider), PresenceStatus.online);

      container.read(presenceInactiveProvider.notifier).state = true;
      await pumpEventQueue();
      expect(own.value, PresenceStatus.idle);
      expect(container.read(ownPresenceProvider), PresenceStatus.idle);

      await container
          .read(presenceSettingsProvider.notifier)
          .setStatus(PresenceStatus.doNotDisturb);
      await pumpEventQueue();
      // Do Not Disturb stays Do Not Disturb while away.
      expect(own.value, PresenceStatus.doNotDisturb);
      expect(presence.savedStatuses, [PresenceStatus.doNotDisturb]);

      await container
          .read(presenceSettingsProvider.notifier)
          .setStatus(PresenceStatus.invisible);
      await pumpEventQueue();
      expect(own.value, isNull);
      expect(container.read(ownPresenceProvider), PresenceStatus.invisible);

      await container
          .read(presenceSettingsProvider.notifier)
          .setStatus(PresenceStatus.online);
      await container
          .read(presenceSettingsProvider.notifier)
          .setShowOnlineStatus(false);
      await pumpEventQueue();
      expect(own.value, isNull);
      expect(container.read(ownPresenceProvider), PresenceStatus.invisible);
      expect(presence.savedShowOnline, [false]);
    });

    test('a failed save puts the old status back', () async {
      presence.saveError = StateError('offline');
      authState.add(const AuthUser(id: 'user-1'));
      final subscription = container.listen(
        presenceSettingsProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);
      await pumpEventQueue();

      await expectLater(
        container
            .read(presenceSettingsProvider.notifier)
            .setStatus(PresenceStatus.idle),
        throwsStateError,
      );
      expect(
        container.read(presenceSettingsProvider).value?.status,
        PresenceStatus.online,
      );
    });
  });
}

class FakePresenceDataSource implements PresenceDataSource {
  Map<String, dynamic>? row;
  final settingsRequests = <String>[];
  final rpcs = <(String, Map<String, dynamic>)>[];
  final joins =
      <({String currentUserId, ValueListenable<PresenceStatus?> ownStatus})>[];
  final updates = StreamController<Map<String, PresenceStatus>>.broadcast();
  var cancelled = false;

  @override
  Future<Map<String, dynamic>?> settings(String userId) async {
    settingsRequests.add(userId);
    return row;
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    rpcs.add((functionName, params));
  }

  @override
  Stream<Map<String, PresenceStatus>> presence({
    required String currentUserId,
    required ValueListenable<PresenceStatus?> ownStatus,
  }) {
    joins.add((currentUserId: currentUserId, ownStatus: ownStatus));
    late StreamController<Map<String, PresenceStatus>> controller;
    StreamSubscription<Map<String, PresenceStatus>>? subscription;
    controller = StreamController<Map<String, PresenceStatus>>(
      onListen: () {
        subscription = updates.stream.listen(controller.add);
      },
      onCancel: () async {
        cancelled = true;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

class FakePresenceRepository implements PresenceRepository {
  final online = StreamController<Map<String, PresenceStatus>>.broadcast();
  var listens = 0;
  var settings = const PresenceSettings();
  Object? saveError;
  ValueListenable<PresenceStatus?>? ownStatus;
  final savedStatuses = <PresenceStatus>[];
  final savedShowOnline = <bool>[];

  @override
  Future<PresenceSettings> loadSettings() async => settings;

  @override
  Future<void> setStatus(PresenceStatus status) async {
    if (saveError case final error?) {
      throw error;
    }
    savedStatuses.add(status);
  }

  @override
  Future<void> setShowOnlineStatus(bool show) async {
    if (saveError case final error?) {
      throw error;
    }
    savedShowOnline.add(show);
  }

  @override
  Stream<Map<String, PresenceStatus>> statuses(
    ValueListenable<PresenceStatus?> ownStatus,
  ) {
    listens += 1;
    this.ownStatus = ownStatus;
    return online.stream;
  }
}
