import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/presence/presence_heartbeat.dart';
import 'package:wecord/shared/app_visibility.dart';

void main() {
  group('PresenceHeartbeat', () {
    late List<bool> beats;
    late ValueNotifier<bool> visible;
    late PresenceHeartbeat heartbeat;

    setUp(() {
      beats = [];
      visible = ValueNotifier(true);
      heartbeat = PresenceHeartbeat(beat: beats.add, visible: visible);
    });

    tearDown(() => heartbeat.dispose());

    test('beats at once and every two minutes while online and visible', () {
      fakeAsync((async) {
        heartbeat.wanted = true;
        expect(beats, [true]);
        async.elapse(const Duration(minutes: 6));
        expect(beats, [true, true, true, true]);
      });
    });

    test('says nothing while the client is not online', () {
      fakeAsync((async) {
        heartbeat.wanted = false;
        async.elapse(const Duration(minutes: 10));
        expect(beats, isEmpty);
      });
    });

    test('rests while the app is hidden, says it left, and starts over when '
        'it can be seen again', () {
      fakeAsync((async) {
        heartbeat.wanted = true;
        async.elapse(const Duration(minutes: 3));
        expect(beats, [true, true]);

        visible.value = false;
        expect(beats, [true, true, false]);
        expect(heartbeat.beating, isFalse);
        async.elapse(const Duration(minutes: 30));
        expect(beats, [true, true, false], reason: 'nothing while hidden');

        visible.value = true;
        expect(beats.last, isTrue, reason: 'back: an immediate beat');
        expect(beats.length, 4);
        async.elapse(const Duration(minutes: 2));
        expect(beats.length, 5);
      });
    });

    test('hidden and offline: coming back does not announce anything', () {
      fakeAsync((async) {
        heartbeat.wanted = true;
        visible.value = false;
        heartbeat.wanted = false;
        beats.clear();
        visible.value = true;
        async.elapse(const Duration(minutes: 10));
        expect(beats, isEmpty);
      });
    });

    test('going offline (Invisible) stops it and says so once', () {
      fakeAsync((async) {
        heartbeat.wanted = true;
        beats.clear();
        heartbeat.wanted = false;
        heartbeat.wanted = false;
        expect(beats, [false]);
        async.elapse(const Duration(minutes: 10));
        expect(beats, [false]);
      });
    });

    test('hidden while already offline says nothing', () {
      fakeAsync((async) {
        heartbeat.wanted = false;
        visible.value = false;
        visible.value = true;
        expect(beats, isEmpty);
      });
    });

    test('disposing says the client left and stops the timer', () {
      fakeAsync((async) {
        heartbeat.wanted = true;
        beats.clear();
        heartbeat.dispose();
        expect(beats, [false]);
        async.elapse(const Duration(minutes: 10));
        expect(beats, [false]);
        visible.value = false;
        visible.value = true;
        expect(beats, [false]);
      });
    });
  });

  group('AppVisibility', () {
    testWidgets('follows the app being hidden, paused and back', (
      tester,
    ) async {
      final visible = AppVisibility.instance.visible;
      expect(visible.value, isTrue);

      void go(AppLifecycleState state) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }

      // Inactive (a system dialog, another window in front): still on screen.
      go(AppLifecycleState.inactive);
      expect(visible.value, isTrue);
      go(AppLifecycleState.hidden);
      expect(visible.value, isFalse);
      go(AppLifecycleState.paused);
      expect(visible.value, isFalse);
      go(AppLifecycleState.hidden);
      go(AppLifecycleState.inactive);
      expect(visible.value, isTrue);
      go(AppLifecycleState.resumed);
      expect(visible.value, isTrue);
    });
  });
}
