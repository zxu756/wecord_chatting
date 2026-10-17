import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_repository.dart';
import 'package:wecord/features/location/location_service.dart';

import 'location_fakes.dart';

const _exact = LatLng(51.50073, -0.12462);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeLocationService service;
  late FakeLocationRepository repository;
  late ProviderContainer container;
  late NotifierProvider<_UserId, String?> userProvider;

  ProviderContainer build() {
    return ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(service),
        locationRepositoryProvider.overrideWithValue(repository),
        locationUserIdProvider.overrideWith((ref) => ref.watch(userProvider)),
      ],
    );
  }

  setUp(() {
    service = FakeLocationService(
      position: DevicePosition(
        point: _exact,
        at: DateTime.utc(2026, 10, 18, 12),
        accuracyMeters: 9,
        heading: 45,
      ),
    );
    repository = FakeLocationRepository();
    userProvider = NotifierProvider<_UserId, String?>(_UserId.new);
    container = build();
  });

  tearDown(() => container.dispose());

  LiveLocationSharer sharer() =>
      container.read(liveLocationSharerProvider.notifier);
  LiveSharingState sharing() => container.read(liveLocationSharerProvider);

  test('nothing is shared until the person starts', () {
    fakeAsync((async) {
      container.listen(liveLocationSharerProvider, (_, _) {});
      async.elapse(const Duration(milliseconds: 1));
      expect(sharing().isSharing, isFalse);
      expect(service.following, isFalse);
      expect(repository.started, isEmpty);
    });
  });

  test('without permission it never starts, and tells the server nothing', () {
    fakeAsync((async) {
      service.current = LocationAccess.denied;
      service.answerWhenAsked = LocationAccess.denied;
      container.listen(liveLocationSharerProvider, (_, _) {});
      Object? error;
      sharer()
          .start(
            conversationId: 'dm-1',
            duration: const Duration(minutes: 15),
            precise: true,
          )
          .then<void>((_) {}, onError: (Object e) => error = e);
      async.elapse(const Duration(milliseconds: 1));
      expect(error, isA<LocationNotAllowed>());
      expect(service.requests, 1);
      expect(repository.started, isEmpty);
      expect(sharing().isSharing, isFalse);
    });
  });

  test(
    'starting asks the server for the chosen time and sends the position',
    () {
      fakeAsync((async) {
        container.listen(liveLocationSharerProvider, (_, _) {});
        sharer().start(
          conversationId: 'dm-1',
          duration: const Duration(hours: 1),
          precise: true,
        );
        async.elapse(const Duration(milliseconds: 1));

        expect(repository.started, [('dm-1', 60, true)]);
        final share = sharing().forConversation('dm-1')!;
        expect(share.precise, isTrue);
        expect(service.following, isTrue);
        expect(service.streamPrecise, [true]);

        final sent = repository.channel(share.shareId).sent;
        expect(sent, isNotEmpty);
        expect(sent.first.point, _exact);
        expect(sent.first.accuracyMeters, 9);
        expect(sent.first.heading, 45);
        expect(sharing().forConversation('dm-1')!.lastPoint, _exact);
      });
    },
  );

  test(
    'a coarse share sends only the snapped position, never the exact one',
    () {
      fakeAsync((async) {
        container.listen(liveLocationSharerProvider, (_, _) {});
        sharer().start(
          conversationId: 'dm-1',
          duration: const Duration(minutes: 15),
          precise: false,
        );
        async.elapse(const Duration(milliseconds: 1));
        final share = sharing().forConversation('dm-1')!;
        final channel = repository.channel(share.shareId);
        service.moveTo(const LatLng(51.50081, -0.12459));
        async.elapse(const Duration(milliseconds: 1));

        expect(service.streamPrecise, [false]);
        expect(channel.sent, isNotEmpty);
        for (final position in channel.sent) {
          expect(position.point, coarsen(_exact));
          expect(position.point, isNot(_exact));
          expect(position.accuracyMeters, isNull);
          expect(position.heading, isNull);
        }
      });
    },
  );

  test(
    'it follows the person and repeats the position while they stand still',
    () {
      fakeAsync((async) {
        container.listen(liveLocationSharerProvider, (_, _) {});
        sharer().start(
          conversationId: 'dm-1',
          duration: const Duration(hours: 1),
          precise: true,
        );
        async.elapse(const Duration(milliseconds: 1));
        final channel = repository.channel(sharing().shares.single.shareId);
        final afterStart = channel.sent.length;

        service.moveTo(westminster);
        async.elapse(const Duration(milliseconds: 1));
        expect(channel.sent.length, afterStart + 1);
        expect(channel.sent.last.point, westminster);

        async.elapse(const Duration(seconds: 10));
        async.elapse(const Duration(milliseconds: 1));
        expect(channel.sent.length, afterStart + 2);
        expect(channel.sent.last.point, westminster);
        async.elapse(const Duration(seconds: 10));
        async.elapse(const Duration(milliseconds: 1));
        expect(channel.sent.length, afterStart + 3);
      });
    },
  );

  test('someone opening the map is answered at once', () {
    fakeAsync((async) {
      container.listen(liveLocationSharerProvider, (_, _) {});
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(hours: 1),
        precise: true,
      );
      async.elapse(const Duration(milliseconds: 1));
      final channel = repository.channel(sharing().shares.single.shareId);
      final before = channel.sent.length;
      channel.listenerJoined();
      async.elapse(const Duration(milliseconds: 1));
      expect(channel.sent.length, before + 1);
    });
  });

  test('it stops by itself when the time is up', () {
    fakeAsync((async) {
      container.listen(liveLocationSharerProvider, (_, _) {});
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(minutes: 15),
        precise: true,
      );
      async.elapse(const Duration(milliseconds: 1));
      final channel = repository.channel(sharing().shares.single.shareId);

      async.elapse(const Duration(minutes: 14));
      async.elapse(const Duration(milliseconds: 1));
      expect(sharing().isSharing, isTrue);
      async.elapse(const Duration(minutes: 1, seconds: 1));
      async.elapse(const Duration(milliseconds: 1));

      expect(sharing().isSharing, isFalse);
      expect(channel.closed, isTrue);
      expect(service.following, isFalse);
      final sentAtEnd = channel.sent.length;
      async.elapse(const Duration(minutes: 5));
      expect(channel.sent.length, sentAtEnd);
    });
  });

  test('Stop ends the share on the server and stops following the person', () {
    fakeAsync((async) {
      container.listen(liveLocationSharerProvider, (_, _) {});
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(hours: 8),
        precise: false,
      );
      async.elapse(const Duration(milliseconds: 1));
      final share = sharing().shares.single;
      final channel = repository.channel(share.shareId);

      Object? err;
      sharer()
          .stop('dm-1')
          .then<void>(
            (_) {},
            onError: (Object e, StackTrace st) {
              err = '$e\n$st';
            },
          );
      async.elapse(const Duration(milliseconds: 1));
      expect(err, isNull);

      expect(repository.stopped, [share.shareId]);
      expect(sharing().isSharing, isFalse);
      expect(channel.closed, isTrue);
      expect(service.following, isFalse);
      final sent = channel.sent.length;
      service.moveTo(westminster);
      async.elapse(const Duration(seconds: 30));
      expect(channel.sent.length, sent);
    });
  });

  test('sharing again in the same chat replaces the earlier share', () {
    fakeAsync((async) {
      container.listen(liveLocationSharerProvider, (_, _) {});
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(minutes: 15),
        precise: false,
      );
      async.elapse(const Duration(milliseconds: 1));
      final first = sharing().shares.single;
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(hours: 1),
        precise: true,
      );
      async.elapse(const Duration(milliseconds: 1));

      expect(sharing().shares, hasLength(1));
      expect(sharing().shares.single.shareId, isNot(first.shareId));
      expect(repository.channel(first.shareId).closed, isTrue);
      // The follower is now exact.
      expect(service.streamPrecise.last, isTrue);
    });
  });

  test('two chats share side by side', () {
    fakeAsync((async) {
      container.listen(liveLocationSharerProvider, (_, _) {});
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(minutes: 15),
        precise: false,
      );
      sharer().start(
        conversationId: 'group-1',
        duration: const Duration(minutes: 60),
        precise: true,
      );
      async.elapse(const Duration(milliseconds: 1));
      expect(sharing().shares, hasLength(2));
      // One reading feeds both, each at its own accuracy.
      final dm = repository.channel(sharing().forConversation('dm-1')!.shareId);
      final group = repository.channel(
        sharing().forConversation('group-1')!.shareId,
      );
      service.moveTo(_exact);
      async.elapse(const Duration(milliseconds: 1));
      expect(dm.sent.last.point, coarsen(_exact));
      expect(group.sent.last.point, _exact);

      sharer().stop('dm-1');
      async.elapse(const Duration(milliseconds: 1));
      expect(sharing().shares.single.conversationId, 'group-1');
      expect(service.following, isTrue);
    });
  });

  test('signing out or changing account ends it here', () {
    fakeAsync((async) {
      container.read(userProvider.notifier).set('user-1');
      container.listen(liveLocationSharerProvider, (_, _) {});
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(hours: 1),
        precise: true,
      );
      async.elapse(const Duration(milliseconds: 1));
      final channel = repository.channel(sharing().shares.single.shareId);

      container.read(userProvider.notifier).set(null);
      async.elapse(const Duration(milliseconds: 1));

      expect(sharing().isSharing, isFalse);
      expect(channel.closed, isTrue);
      expect(service.following, isFalse);
    });
  });

  test('stopAll ends every share, here and on the server', () {
    fakeAsync((async) {
      container.listen(liveLocationSharerProvider, (_, _) {});
      sharer().start(
        conversationId: 'dm-1',
        duration: const Duration(minutes: 15),
        precise: false,
      );
      sharer().start(
        conversationId: 'group-1',
        duration: const Duration(minutes: 15),
        precise: false,
      );
      async.elapse(const Duration(milliseconds: 1));
      sharer().stopAll();
      async.elapse(const Duration(milliseconds: 1));
      expect(sharing().isSharing, isFalse);
      expect(repository.stopAllCalls, 1);
    });
  });

  group('after the app was restarted', () {
    OwnShare running() => OwnShare(
      shareId: 'share-old',
      conversationId: 'dm-1',
      endsAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      precise: true,
    );

    test('a share still running carries on when location is allowed', () {
      fakeAsync((async) {
        container.dispose();
        repository.mine = [running()];
        container = build();
        container.read(userProvider.notifier).set('user-1');
        container.listen(liveLocationSharerProvider, (_, _) {});
        async.elapse(const Duration(milliseconds: 1));

        expect(sharing().forConversation('dm-1')?.shareId, 'share-old');
        expect(service.following, isTrue);
        expect(repository.channel('share-old').sent, isNotEmpty);
      });
    });

    test(
      'with location no longer allowed it is ended, not left looking alive',
      () {
        fakeAsync((async) {
          container.dispose();
          service.current = LocationAccess.deniedForever;
          repository.mine = [running()];
          container = build();
          container.read(userProvider.notifier).set('user-1');
          container.listen(liveLocationSharerProvider, (_, _) {});
          async.elapse(const Duration(milliseconds: 1));

          expect(sharing().isSharing, isFalse);
          expect(repository.stopAllCalls, 1);
          expect(service.following, isFalse);
        });
      },
    );

    test('nobody signed in resumes nothing', () {
      fakeAsync((async) {
        container.dispose();
        repository.mine = [running()];
        container = build();
        container.read(userProvider.notifier).set(null);
        container.listen(liveLocationSharerProvider, (_, _) {});
        async.elapse(const Duration(milliseconds: 1));
        expect(sharing().isSharing, isFalse);
      });
    });
  });
}

class _UserId extends Notifier<String?> {
  @override
  String? build() => 'user-1';

  void set(String? value) => state = value;
}
