import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';

void main() {
  test('tracks the current user when online status is shown', () async {
    final dataSource = FakePresenceDataSource()..showOnlineStatusValue = true;
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final updates = <Set<String>>[];
    final subscription = repository.onlineUserIds().listen(updates.add);
    await pumpEventQueue();
    dataSource.updates.add({'user-1'});
    dataSource.updates.add({'user-1', 'user-2'});
    await pumpEventQueue();
    await subscription.cancel();

    expect(dataSource.privacyRequests, ['user-1']);
    expect(dataSource.joins, [(currentUserId: 'user-1', trackSelf: true)]);
    expect(updates, [
      {'user-1'},
      {'user-1', 'user-2'},
    ]);
    expect(dataSource.cancelled, isTrue);
  });

  test('missing privacy settings default to showing online status', () async {
    final dataSource = FakePresenceDataSource();
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final subscription = repository.onlineUserIds().listen((_) {});
    await pumpEventQueue();
    await subscription.cancel();

    expect(dataSource.joins.single.trackSelf, isTrue);
  });

  test('hidden online status watches without tracking', () async {
    final dataSource = FakePresenceDataSource()..showOnlineStatusValue = false;
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final updates = <Set<String>>[];
    final subscription = repository.onlineUserIds().listen(updates.add);
    await pumpEventQueue();
    dataSource.updates.add({'user-2'});
    await pumpEventQueue();
    await subscription.cancel();

    expect(dataSource.joins, [(currentUserId: 'user-1', trackSelf: false)]);
    expect(updates, [
      {'user-2'},
    ]);
  });

  test('an unreadable privacy setting still tracks', () async {
    final dataSource = FakePresenceDataSource()
      ..privacyError = StateError('offline');
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final subscription = repository.onlineUserIds().listen((_) {});
    await pumpEventQueue();
    await subscription.cancel();

    expect(dataSource.joins.single.trackSelf, isTrue);
  });

  test('signed out yields nobody and joins nothing', () async {
    final dataSource = FakePresenceDataSource();
    final repository = SupabasePresenceRepository.withDataSource(
      dataSource,
      currentUserId: () => null,
    );

    expect(await repository.onlineUserIds().toList(), [<String>{}]);
    expect(dataSource.joins, isEmpty);
  });

  test('onlineUserIdsProvider joins only while signed in', () async {
    final presence = FakePresenceRepository();
    final authState = StreamController<AuthUser?>.broadcast();
    final container = ProviderContainer(
      overrides: [
        presenceRepositoryProvider.overrideWithValue(presence),
        authStateProvider.overrideWith((ref) => authState.stream),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      onlineUserIdsProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);

    authState.add(null);
    await pumpEventQueue();
    expect(container.read(onlineUserIdsProvider).valueOrNull, <String>{});
    expect(presence.listens, 0);

    authState.add(const AuthUser(id: 'user-1'));
    await pumpEventQueue();
    presence.online.add({'user-1', 'user-2'});
    await pumpEventQueue();
    expect(presence.listens, 1);
    expect(container.read(onlineUserIdsProvider).valueOrNull, {
      'user-1',
      'user-2',
    });
  });
}

class FakePresenceDataSource implements PresenceDataSource {
  bool? showOnlineStatusValue;
  Object? privacyError;
  final privacyRequests = <String>[];
  final joins = <({String currentUserId, bool trackSelf})>[];
  final updates = StreamController<Set<String>>.broadcast();
  var cancelled = false;

  @override
  Future<bool?> showOnlineStatus(String userId) async {
    privacyRequests.add(userId);
    if (privacyError case final error?) {
      throw error;
    }
    return showOnlineStatusValue;
  }

  @override
  Stream<Set<String>> presence({
    required String currentUserId,
    required bool trackSelf,
  }) {
    joins.add((currentUserId: currentUserId, trackSelf: trackSelf));
    late StreamController<Set<String>> controller;
    StreamSubscription<Set<String>>? subscription;
    controller = StreamController<Set<String>>(
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
  final online = StreamController<Set<String>>.broadcast();
  var listens = 0;

  @override
  Stream<Set<String>> onlineUserIds() {
    listens += 1;
    return online.stream;
  }
}
