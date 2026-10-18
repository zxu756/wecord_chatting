import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/error_reports/anomaly_detectors.dart';

final _t0 = DateTime.utc(2026, 10, 19, 12);

void main() {
  group('UnexpectedSignOutDetector', () {
    test('a sign-out nobody asked for is unexpected', () {
      final detector = UnexpectedSignOutDetector();
      expect(detector.signedOut(_t0), isTrue);
    });

    test('a sign-out right after expectSignOut is expected', () {
      final detector = UnexpectedSignOutDetector()..expectSignOut(_t0);
      expect(detector.signedOut(_t0.add(const Duration(seconds: 2))), isFalse);
      // More than one event for the same sign-out is still expected.
      expect(detector.signedOut(_t0.add(const Duration(seconds: 3))), isFalse);
    });

    test('the expectation runs out', () {
      final detector = UnexpectedSignOutDetector()..expectSignOut(_t0);
      expect(detector.signedOut(_t0.add(const Duration(minutes: 5))), isTrue);
    });

    test('a longer window can be asked for', () {
      final detector = UnexpectedSignOutDetector()
        ..expectSignOut(_t0, within: const Duration(minutes: 2));
      expect(detector.signedOut(_t0.add(const Duration(minutes: 1))), isFalse);
    });

    test('signing in again ends the expectation', () {
      final detector = UnexpectedSignOutDetector()
        ..expectSignOut(_t0)
        ..signedIn();
      expect(detector.signedOut(_t0.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('RefreshBurstDetector', () {
    test('a few refreshes are normal', () {
      final detector = RefreshBurstDetector(threshold: 5);
      for (var i = 0; i < 5; i++) {
        expect(detector.record(_t0.add(Duration(seconds: i * 10))), isNull);
      }
    });

    test('more than the threshold within a minute is a burst, once', () {
      final detector = RefreshBurstDetector(threshold: 5);
      int? burst;
      var bursts = 0;
      for (var i = 0; i < 20; i++) {
        final result = detector.record(
          _t0.add(Duration(milliseconds: i * 500)),
        );
        if (result != null) {
          burst = result;
          bursts++;
        }
      }
      expect(burst, 6);
      expect(bursts, 1);
    });

    test('slow refreshes spread over time are not a burst', () {
      final detector = RefreshBurstDetector(threshold: 3);
      for (var i = 0; i < 30; i++) {
        expect(detector.record(_t0.add(Duration(minutes: i))), isNull);
      }
    });

    test('a second burst after the quiet period is reported again', () {
      final detector = RefreshBurstDetector(threshold: 2);
      var bursts = 0;
      for (var round = 0; round < 2; round++) {
        final start = _t0.add(Duration(minutes: 10 * round));
        for (var i = 0; i < 5; i++) {
          if (detector.record(start.add(Duration(seconds: i))) != null) {
            bursts++;
          }
        }
      }
      expect(bursts, 2);
    });
  });

  group('RedirectLoopDetector', () {
    test('the same redirect more than N times in seconds is a loop', () {
      final detector = RedirectLoopDetector(threshold: 4);
      int? loop;
      for (var i = 0; i < 6; i++) {
        loop ??= detector.record(
          '/home',
          '/auth',
          _t0.add(Duration(milliseconds: i * 100)),
        );
      }
      expect(loop, 5);
    });

    test('it is reported once per cooldown', () {
      final detector = RedirectLoopDetector(threshold: 2);
      var reports = 0;
      for (var i = 0; i < 50; i++) {
        if (detector.record(
              '/a',
              '/b',
              _t0.add(Duration(milliseconds: i * 10)),
            ) !=
            null) {
          reports++;
        }
      }
      expect(reports, 1);
    });

    test('redirects spread over time are not a loop', () {
      final detector = RedirectLoopDetector(threshold: 3);
      for (var i = 0; i < 20; i++) {
        expect(
          detector.record('/a', '/b', _t0.add(Duration(seconds: i * 3))),
          isNull,
        );
      }
    });

    test('different redirects are counted apart', () {
      final detector = RedirectLoopDetector(threshold: 3);
      for (var i = 0; i < 12; i++) {
        expect(
          detector.record('/a$i', '/b', _t0.add(Duration(milliseconds: i))),
          isNull,
        );
      }
    });

    test('a bounce between two routes counts each direction', () {
      final detector = RedirectLoopDetector(threshold: 3);
      final loops = <int>[];
      for (var i = 0; i < 12; i++) {
        final at = _t0.add(Duration(milliseconds: i * 10));
        final result = i.isEven
            ? detector.record('/a', '/b', at)
            : detector.record('/b', '/a', at);
        if (result != null) {
          loops.add(result);
        }
      }
      expect(loops, hasLength(2));
    });
  });
}
