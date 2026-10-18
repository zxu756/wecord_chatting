import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/live_location_providers.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_repository.dart';
import 'package:wecord/shared/app_visibility.dart';

import 'location_fakes.dart';

void main() {
  late FakeLocationRepository repository;
  late ProviderContainer container;
  late ValueNotifier<bool> visible;

  setUp(() {
    repository = FakeLocationRepository();
    visible = ValueNotifier(true);
    container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(repository),
        locationUserIdProvider.overrideWithValue('user-1'),
        appVisibleProvider.overrideWithValue(visible),
      ],
    );
  });

  tearDown(() => container.dispose());

  LivePosition at(double lat, double lng, {int secondsAgo = 0}) => LivePosition(
    point: LatLng(lat, lng),
    at: DateTime.now().toUtc().subtract(Duration(seconds: secondsAgo)),
  );

  group('who is sharing', () {
    test('lists the running shares and follows starts and stops', () {
      fakeAsync((async) {
        repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
        final seen = <List<String>>[];
        container.listen(liveSharesProvider('group-1'), (_, next) {
          if (next.hasValue) {
            seen.add([for (final share in next.value!) share.name]);
          }
        });
        async.elapse(const Duration(milliseconds: 10));
        expect(seen.last, ['Ada']);

        repository.addShare(otherShare('s-bob', 'user-3', 'Bob'));
        async.elapse(const Duration(seconds: 1));
        expect(seen.last, ['Ada', 'Bob']);

        repository.stopped.add('s-ada');
        repository.pingChanged();
        async.elapse(const Duration(seconds: 1));
        expect(seen.last, ['Bob']);
      });
    });

    test('a share drops out the moment its time is up', () {
      fakeAsync((async) {
        repository.addShare(
          otherShare(
            's-ada',
            'user-2',
            'Ada',
            left: const Duration(minutes: 2),
          ),
        );
        final seen = <int>[];
        container.listen(liveSharesProvider('group-1'), (_, next) {
          if (next.hasValue) {
            seen.add(next.value!.length);
          }
        });
        async.elapse(const Duration(seconds: 1));
        expect(seen.last, 1);
        async.elapse(const Duration(minutes: 2));
        expect(seen.last, 0);
      });
    });

    test(
      'the list is checked again now and then (a block or a deleted card)',
      () {
        fakeAsync((async) {
          container.listen(liveSharesProvider('group-1'), (_, _) {});
          async.elapse(const Duration(seconds: 1));
          repository.shares.add(otherShare('s-late', 'user-2', 'Late'));
          async.elapse(liveSharesRefresh);
          expect(
            container
                .read(liveSharesProvider('group-1'))
                .value!
                .map((s) => s.name),
            ['Late'],
          );
        });
      },
    );

    test('the polling rests while the app is hidden and catches up when it '
        'is back', () {
      fakeAsync((async) {
        container.listen(liveSharesProvider('group-1'), (_, _) {});
        async.elapse(const Duration(seconds: 1));
        expect(repository.listSharesCalls, 1);

        // Visible: one check every 45 s.
        async.elapse(liveSharesRefresh * 2);
        expect(repository.listSharesCalls, 3);

        // Hidden for ten minutes: no checks at all.
        visible.value = false;
        async.elapse(const Duration(minutes: 10));
        expect(repository.listSharesCalls, 3);

        // Someone started sharing meanwhile (and no message told us): the
        // list is read the moment the app is back, and polling starts again.
        repository.shares.add(otherShare('s-late', 'user-2', 'Late'));
        visible.value = true;
        async.elapse(const Duration(milliseconds: 10));
        expect(repository.listSharesCalls, 4);
        expect(
          container
              .read(liveSharesProvider('group-1'))
              .value!
              .map((s) => s.name),
          ['Late'],
        );
        async.elapse(liveSharesRefresh);
        expect(repository.listSharesCalls, 5);
      });
    });

    test('a share still ends on time while the app is hidden', () {
      fakeAsync((async) {
        repository.addShare(
          otherShare(
            's-ada',
            'user-2',
            'Ada',
            left: const Duration(minutes: 2),
          ),
        );
        final seen = <int>[];
        container.listen(liveSharesProvider('group-1'), (_, next) {
          if (next.hasValue) {
            seen.add(next.value!.length);
          }
        });
        async.elapse(const Duration(seconds: 1));
        expect(seen.last, 1);

        visible.value = false;
        async.elapse(const Duration(minutes: 2, seconds: 5));
        expect(seen.last, 0, reason: 'the expiry does not wait for polling');
        expect(repository.listSharesCalls, 1);
      });
    });

    test('hiding and showing the app quickly does not start two polls', () {
      fakeAsync((async) {
        container.listen(liveSharesProvider('group-1'), (_, _) {});
        async.elapse(const Duration(seconds: 1));
        for (var i = 0; i < 5; i++) {
          visible.value = false;
          visible.value = true;
        }
        async.elapse(const Duration(milliseconds: 10));
        final before = repository.listSharesCalls;
        async.elapse(liveSharesRefresh);
        expect(repository.listSharesCalls, before + 1);
      });
    });

    test('equal lists are not announced twice', () {
      fakeAsync((async) {
        repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
        var emissions = 0;
        container.listen(liveSharesProvider('group-1'), (_, next) {
          if (next.hasValue) {
            emissions += 1;
          }
        });
        async.elapse(const Duration(seconds: 1));
        repository.pingChanged();
        async.elapse(const Duration(seconds: 1));
        repository.pingChanged();
        async.elapse(const Duration(seconds: 1));
        expect(emissions, 1);
      });
    });
  });

  group('where they are', () {
    test(
      'listens to everyone but this person, and asks for the latest position',
      () {
        fakeAsync((async) {
          repository.addShare(otherShare('s-me', 'user-1', 'Me'));
          repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
          container.listen(livePositionsProvider('group-1'), (_, _) {});
          async.elapse(const Duration(seconds: 1));

          expect(repository.channels.keys, ['s-ada']);
          expect(repository.channel('s-ada').latestRequests, 1);
        });
      },
    );

    test('keeps the latest position of each person, newest wins', () {
      fakeAsync((async) {
        repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
        container.listen(livePositionsProvider('group-1'), (_, _) {});
        async.elapse(const Duration(seconds: 1));
        final channel = repository.channel('s-ada');

        channel.receive(at(51.5, -0.12, secondsAgo: 5));
        async.elapse(const Duration(milliseconds: 10));
        channel.receive(at(51.6, -0.12));
        async.elapse(const Duration(milliseconds: 10));
        // A late one does not move her back.
        channel.receive(at(51.4, -0.12, secondsAgo: 30));
        async.elapse(const Duration(milliseconds: 10));

        final positions = container.read(livePositionsProvider('group-1'));
        expect(positions.latest['user-2']!.point.latitude, 51.6);
      });
    });

    test(
      'a share the server refuses is marked, and clears when positions come',
      () {
        fakeAsync((async) {
          repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
          container.listen(livePositionsProvider('group-1'), (_, _) {});
          async.elapse(const Duration(seconds: 1));
          final channel = repository.channel('s-ada');

          channel.refuse();
          async.elapse(const Duration(milliseconds: 10));
          expect(container.read(livePositionsProvider('group-1')).unavailable, {
            'user-2',
          });
          channel.receive(at(51.5, -0.12));
          async.elapse(const Duration(milliseconds: 10));
          expect(
            container.read(livePositionsProvider('group-1')).unavailable,
            isEmpty,
          );
        });
      },
    );

    test('when somebody stops, their channel closes and their dot goes', () {
      fakeAsync((async) {
        repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
        repository.addShare(otherShare('s-bob', 'user-3', 'Bob'));
        container.listen(livePositionsProvider('group-1'), (_, _) {});
        async.elapse(const Duration(seconds: 1));
        repository.channel('s-ada').receive(at(51.5, -0.12));
        repository.channel('s-bob').receive(at(51.6, -0.13));
        async.elapse(const Duration(milliseconds: 10));

        repository.stopped.add('s-ada');
        repository.pingChanged();
        async.elapse(const Duration(seconds: 1));

        expect(repository.channel('s-ada').closed, isTrue);
        expect(repository.channel('s-bob').closed, isFalse);
        expect(container.read(livePositionsProvider('group-1')).latest.keys, [
          'user-3',
        ]);
      });
    });

    test('leaving the map closes every channel', () {
      fakeAsync((async) {
        repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
        final subscription = container.listen(
          livePositionsProvider('group-1'),
          (_, _) {},
        );
        async.elapse(const Duration(seconds: 1));
        subscription.close();
        async.elapse(const Duration(seconds: 1));
        expect(repository.channel('s-ada').closed, isTrue);
      });
    });

    test('positions are kept in memory only: a new map starts empty', () {
      fakeAsync((async) {
        repository.addShare(otherShare('s-ada', 'user-2', 'Ada'));
        var subscription = container.listen(
          livePositionsProvider('group-1'),
          (_, _) {},
        );
        async.elapse(const Duration(seconds: 1));
        repository.channel('s-ada').receive(at(51.5, -0.12));
        async.elapse(const Duration(milliseconds: 10));
        expect(
          container.read(livePositionsProvider('group-1')).latest,
          isNotEmpty,
        );
        subscription.close();
        async.elapse(const Duration(seconds: 1));
        subscription = container.listen(
          livePositionsProvider('group-1'),
          (_, _) {},
        );
        async.elapse(const Duration(seconds: 1));
        expect(
          container.read(livePositionsProvider('group-1')).latest,
          isEmpty,
        );
      });
    });
  });
}
