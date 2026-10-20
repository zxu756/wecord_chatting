import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/error_reports/breadcrumbs.dart';
import 'package:wecord/features/error_reports/error_report_io.dart';
import 'package:wecord/features/error_reports/error_reporter.dart';

class _Sink implements ErrorReportSink {
  final batches = <List<Map<String, Object?>>>[];
  Object? failWith;
  Completer<void>? hold;

  List<Map<String, Object?>> get all => [for (final b in batches) ...b];

  @override
  Future<void> send(List<Map<String, Object?>> reports) async {
    if (hold != null) {
      await hold!.future;
    }
    final error = failWith;
    if (error != null) {
      throw error;
    }
    batches.add(reports);
  }
}

class _ThrowingStore implements ErrorReportStore {
  @override
  Future<bool?> loadEnabled() => throw StateError('no storage');

  @override
  Future<List<Map<String, Object?>>> loadQueue() => throw StateError('no');

  @override
  Future<void> saveEnabled(bool enabled) => throw StateError('no');

  @override
  Future<void> saveQueue(List<Map<String, Object?>> queue) =>
      throw StateError('no');
}

ErrorReporter _reporter({
  DateTime Function()? clock,
  int maxNewPerWindow = 30,
  int maxUploadsPerHour = 60,
  int maxQueue = 30,
}) => ErrorReporter(
  clock: clock,
  maxNewPerWindow: maxNewPerWindow,
  maxUploadsPerHour: maxUploadsPerHour,
  maxQueue: maxQueue,
  environment: const ReporterEnvironment(
    platform: 'macos',
    appVersion: '1.2.3',
    build: '45',
  ),
);

/// An error with a distinct message per [i], so each has its own
/// fingerprint.
Never _fail(int i) => throw StateError('problem number-$i-x');

/// Fingerprints ignore digits, so a number in [name] becomes letters.
void _report(ErrorReporter reporter, String name, {int times = 1}) {
  final distinct = name.replaceAllMapped(
    RegExp(r'\d'),
    (m) => String.fromCharCode(97 + int.parse(m[0]!)),
  );
  for (var i = 0; i < times; i++) {
    reporter.reportAnomaly(
      ErrorKind.rpcError,
      'rpc $distinct failed: status=400 code=-',
    );
  }
}

void main() {
  test(
    'a report carries kind, scrubbed message, stack, fingerprint, context',
    () async {
      final sink = _Sink();
      final reporter = _reporter()
        ..routeProvider = (() => '/chats/:id')
        ..localeProvider = (() => 'zh')
        ..noteRoute('/chats/:id')
        ..noteLifecycle('resumed');
      await reporter.start(sink: sink, store: InMemoryErrorReportStore());
      try {
        throw StateError('secret text hello@example.com');
      } on StateError catch (error, stack) {
        reporter.report(ErrorKind.flutterError, error, stack);
      }
      await reporter.flush();
      final report = sink.all.single;
      expect(report['kind'], 'flutter_error');
      expect(report['message'], isNot(contains('hello@example.com')));
      expect(report['message'], contains('<email>'));
      expect(report['fingerprint'], matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(report['platform'], 'macos');
      expect(report['app_version'], '1.2.3');
      expect(report['build'], '45');
      expect(report['count'], 1);
      expect(report['stack'], isA<String>());
      final context = report['context']! as Map;
      expect(context['route'], '/chats/:id');
      expect(context['locale'], 'zh');
      expect(context['crumbs'], hasLength(2));
      // The class of the error, for grouping on the server (K5).
      expect(context['type'], 'StateError');
      expect(report.containsKey('user_id'), isFalse);
      reporter.dispose();
    },
  );

  test('breadcrumbs keep the last 30 only', () {
    final crumbs = Breadcrumbs();
    for (var i = 0; i < 100; i++) {
      crumbs.add('route', '/r$i');
    }
    expect(crumbs.items, hasLength(30));
    expect(crumbs.items.first.label, '/r70');
    expect(crumbs.recent(), hasLength(8));
    expect(crumbs.recent().last['v'], '/r99');
  });

  group('dedupe', () {
    test('the same problem is one report with a count', () async {
      final sink = _Sink();
      final reporter = _reporter();
      await reporter.start(sink: sink, store: InMemoryErrorReportStore());
      _report(reporter, 'a', times: 7);
      expect(reporter.pendingCount, 1);
      await reporter.flush();
      expect(sink.all.single['count'], 7);
      reporter.dispose();
    });

    test('different problems are separate', () async {
      final sink = _Sink();
      final reporter = _reporter();
      await reporter.start(sink: sink, store: InMemoryErrorReportStore());
      _report(reporter, 'a');
      _report(reporter, 'b');
      await reporter.flush();
      expect(sink.all, hasLength(2));
      reporter.dispose();
    });

    test('a problem sent a moment ago waits out the cooldown', () {
      fakeAsync((async) {
        final sink = _Sink();
        final reporter = _reporter(
          clock: () => async.getClock(DateTime.utc(2026)).now(),
        );
        reporter.start(sink: sink, store: InMemoryErrorReportStore());
        async.flushMicrotasks();
        _report(reporter, 'a', times: 2);
        async.elapse(const Duration(seconds: 25));
        expect(sink.all, hasLength(1));
        expect(sink.all.single['count'], 2);

        _report(reporter, 'a', times: 3);
        async.elapse(const Duration(minutes: 5));
        expect(sink.all, hasLength(1));
        async.elapse(const Duration(minutes: 6));
        expect(sink.all, hasLength(2));
        expect(sink.all.last['count'], 3);
        reporter.dispose();
      });
    });

    test(
      'occurrences while an upload is in flight go in the next one',
      () async {
        final sink = _Sink()..hold = Completer<void>();
        final reporter = _reporter();
        await reporter.start(sink: sink, store: InMemoryErrorReportStore());
        _report(reporter, 'a', times: 2);
        final flushing = reporter.flush();
        await Future<void>.delayed(Duration.zero);
        _report(reporter, 'a', times: 4);
        sink.hold!.complete();
        await flushing;
        expect(sink.all.single['count'], 2);
        expect(reporter.pending.single.count, 4);
        reporter.dispose();
      },
    );
  });

  group('device rate limits', () {
    test(
      'only so many new problems per window; the rest are counted',
      () async {
        final sink = _Sink();
        final reporter = _reporter(maxNewPerWindow: 5);
        await reporter.start(sink: sink, store: InMemoryErrorReportStore());
        for (var i = 0; i < 20; i++) {
          _report(reporter, 'p$i');
        }
        expect(reporter.pendingCount, 5);
        expect(reporter.dropped, 15);
        reporter.dispose();
      },
    );

    test('the window moves on', () {
      var now = DateTime.utc(2026);
      final reporter = _reporter(clock: () => now, maxNewPerWindow: 2);
      _report(reporter, 'a');
      _report(reporter, 'b');
      _report(reporter, 'c');
      expect(reporter.pendingCount, 2);
      now = now.add(const Duration(minutes: 11));
      _report(reporter, 'c');
      expect(reporter.pendingCount, 3);
      reporter.dispose();
    });

    test('the queue is bounded', () {
      final reporter = _reporter(maxQueue: 3);
      for (var i = 0; i < 10; i++) {
        _report(reporter, 'p$i');
      }
      expect(reporter.pendingCount, 3);
      reporter.dispose();
    });

    test('uploads stay under the hourly allowance', () {
      fakeAsync((async) {
        final sink = _Sink();
        final reporter = ErrorReporter(
          clock: () => async.getClock(DateTime.utc(2026)).now(),
          maxBatch: 2,
          maxUploadsPerHour: 3,
          sameProblemCooldown: Duration.zero,
        );
        reporter.start(sink: sink, store: InMemoryErrorReportStore());
        async.flushMicrotasks();
        for (var i = 0; i < 8; i++) {
          _report(reporter, 'p$i');
        }
        async.elapse(const Duration(minutes: 30));
        expect(sink.all, hasLength(3));
        async.elapse(const Duration(minutes: 40));
        expect(sink.all.length, greaterThan(3));
        reporter.dispose();
      });
    });

    test('a batch holds at most maxBatch reports', () async {
      final sink = _Sink();
      final reporter = ErrorReporter(maxBatch: 4);
      await reporter.start(sink: sink, store: InMemoryErrorReportStore());
      for (var i = 0; i < 10; i++) {
        _report(reporter, 'p$i');
      }
      await reporter.flush();
      expect(sink.batches.single, hasLength(4));
      reporter.dispose();
    });
  });

  group('offline queue', () {
    test('a failed upload keeps the report and backs off, then sends', () {
      fakeAsync((async) {
        final sink = _Sink()..failWith = Exception('offline');
        final store = InMemoryErrorReportStore();
        final reporter = ErrorReporter(
          clock: () => async.getClock(DateTime.utc(2026)).now(),
        );
        reporter.start(sink: sink, store: store);
        async.flushMicrotasks();
        _report(reporter, 'a');
        async.elapse(const Duration(seconds: 25));
        expect(reporter.pendingCount, 1);
        expect(store.queue, hasLength(1));

        sink.failWith = null;
        async.elapse(const Duration(minutes: 2));
        expect(sink.all, hasLength(1));
        expect(reporter.pendingCount, 0);
        expect(store.queue, isEmpty);
        reporter.dispose();
      });
    });

    test('the queue survives a restart', () async {
      final store = InMemoryErrorReportStore();
      final first = _reporter();
      await first.start(sink: null, store: store);
      _report(first, 'a');
      await Future<void>.delayed(Duration.zero);
      expect(store.queue, hasLength(1));
      first.dispose();

      final sink = _Sink();
      final second = _reporter();
      await second.start(sink: sink, store: store);
      expect(second.pendingCount, 1);
      await second.flush();
      expect(sink.all, hasLength(1));
      second.dispose();
    });

    test('a refused batch is dropped, not sent again', () async {
      final sink = _Sink()..failWith = const ErrorReportRejected();
      final reporter = _reporter();
      await reporter.start(sink: sink, store: InMemoryErrorReportStore());
      _report(reporter, 'a');
      await reporter.flush();
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });

    test('a damaged queue entry is skipped', () async {
      final store = InMemoryErrorReportStore(
        queue: [
          {'garbage': true},
        ],
      );
      final reporter = _reporter();
      await reporter.start(store: store);
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });
  });

  group('never crashes or loops itself', () {
    test('failing uploads and storage are never reported', () async {
      final sink = _Sink()..failWith = StateError('boom');
      final reporter = _reporter();
      await reporter.start(sink: sink, store: _ThrowingStore());
      _report(reporter, 'a');
      await reporter.flush();
      await reporter.flush();
      expect(reporter.pendingCount, 1);
      expect(sink.all, isEmpty);
      reporter.dispose();
    });

    test('a report made while reporting is dropped', () {
      final reporter = _reporter();
      reporter.report(ErrorKind.flutterError, _Reentrant(reporter), null);
      expect(reporter.pendingCount, 1);
      reporter.dispose();
    });

    test('an error whose toString throws is still handled', () {
      final reporter = _reporter();
      reporter.report(ErrorKind.zoneError, _BadToString(), StackTrace.current);
      expect(reporter.pendingCount, 1);
      reporter.dispose();
    });

    test(
      'reports made before start() wait, and are dropped when off',
      () async {
        final reporter = _reporter();
        _report(reporter, 'early');
        expect(reporter.pendingCount, 1);
        await reporter.start(
          sink: _Sink(),
          store: InMemoryErrorReportStore(enabled: false),
        );
        expect(reporter.pendingCount, 0);
        reporter.dispose();
      },
    );
  });

  group('opt-out', () {
    test('when off nothing is kept or sent', () async {
      final sink = _Sink();
      final store = InMemoryErrorReportStore();
      final reporter = _reporter();
      await reporter.start(sink: sink, store: store);
      _report(reporter, 'a');
      expect(reporter.pendingCount, 1);
      await reporter.setEnabled(false);
      expect(reporter.pendingCount, 0);
      expect(store.enabled, isFalse);
      _report(reporter, 'b');
      try {
        _fail(1);
      } on StateError catch (e, s) {
        reporter.report(ErrorKind.zoneError, e, s);
      }
      reporter.noteAuthEvent('signedOut');
      await reporter.flush();
      expect(reporter.pendingCount, 0);
      expect(sink.all, isEmpty);
      reporter.dispose();
    });

    test('the choice is remembered and applies again', () async {
      final store = InMemoryErrorReportStore(enabled: false);
      final reporter = _reporter();
      await reporter.start(sink: _Sink(), store: store);
      expect(reporter.enabled, isFalse);
      await reporter.setEnabled(true);
      expect(store.enabled, isTrue);
      _report(reporter, 'a');
      expect(reporter.pendingCount, 1);
      reporter.dispose();
    });

    test('on by default', () async {
      final reporter = _reporter();
      await reporter.start(sink: _Sink(), store: InMemoryErrorReportStore());
      expect(reporter.enabled, isTrue);
      reporter.dispose();
    });
  });

  group('auth anomalies', () {
    test('a sign-out nobody asked for is reported once', () {
      final reporter = _reporter();
      reporter.noteAuthEvent('signedIn');
      reporter.noteAuthEvent('signedOut');
      reporter.noteAuthEvent('signedOut');
      expect(reporter.pending.single.kind, 'auth_unexpected_sign_out');
      expect(reporter.pending.single.count, 2);
      reporter.dispose();
    });

    test('a sign-out the user asked for is not', () {
      final reporter = _reporter();
      reporter.noteAuthEvent('signedIn');
      reporter.expectSignOut();
      reporter.noteAuthEvent('signedOut');
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });

    test('a burst of token refreshes is reported with the count', () {
      final reporter = _reporter();
      for (var i = 0; i < 12; i++) {
        reporter.noteAuthEvent('tokenRefreshed');
      }
      final report = reporter.pending.single;
      expect(report.kind, 'auth_refresh_burst');
      expect(report.message, contains('6 token refreshes'));
      reporter.dispose();
    });

    test('auth events become breadcrumbs', () {
      final reporter = _reporter();
      reporter.noteAuthEvent('signedIn');
      reporter.noteAuthEvent('tokenRefreshed');
      expect(reporter.breadcrumbs.items.map((c) => c.label), [
        'signedIn',
        'tokenRefreshed',
      ]);
      reporter.dispose();
    });

    test('a redirect loop is reported with routes but no ids', () {
      final reporter = _reporter();
      for (var i = 0; i < 12; i++) {
        reporter.noteRedirect(
          '/chats/8f14e45f-ceea-467a-9d1e-0123456789ab',
          '/auth',
        );
      }
      final report = reporter.pending.single;
      expect(report.kind, 'router_redirect_loop');
      expect(report.message, contains('/chats/:id'));
      expect(report.message, isNot(contains('8f14e45f')));
      reporter.dispose();
    });
  });

  group('failed requests', () {
    test('server errors and auth trouble are reported with codes only', () {
      final reporter = _reporter();
      reporter.noteRequestFailure(
        kind: ErrorKind.rpcError,
        name: 'list_chats',
        status: 500,
        code: 'XX000',
      );
      reporter.noteRequestFailure(
        kind: ErrorKind.functionError,
        name: 'sessions',
        status: 401,
      );
      expect(reporter.pending.map((r) => r.message), [
        'rpc list_chats failed: status=500 code=XX000',
        'call sessions failed: status=401 code=-',
      ]);
      reporter.dispose();
    });

    test('rules the server refuses on purpose are not reported', () {
      final reporter = _reporter();
      for (final code in ['P0001', '23505', '22023', null]) {
        reporter.noteRequestFailure(
          kind: ErrorKind.rpcError,
          name: 'create_thing',
          status: 400,
          code: code,
        );
      }
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });

    test('a missing function or a privilege problem is reported', () {
      final reporter = _reporter();
      reporter.noteRequestFailure(
        kind: ErrorKind.rpcError,
        name: 'gone',
        status: 400,
        code: '42883',
      );
      reporter.noteRequestFailure(
        kind: ErrorKind.rpcError,
        name: 'gone2',
        status: 404,
        code: 'PGRST202',
      );
      expect(reporter.pendingCount, 2);
      reporter.dispose();
    });

    test('a wrong password is not reported, a sign-in outage is', () {
      final reporter = _reporter();
      reporter.noteRequestFailure(
        kind: ErrorKind.signInError,
        name: 'token',
        status: 400,
        code: 'invalid_credentials',
      );
      expect(reporter.pendingCount, 0);
      reporter.noteRequestFailure(
        kind: ErrorKind.signInError,
        name: 'token',
        status: 503,
      );
      expect(reporter.pendingCount, 1);
      reporter.dispose();
    });

    test('odd names and codes are replaced, not sent', () {
      final reporter = _reporter();
      reporter.noteRequestFailure(
        kind: ErrorKind.rpcError,
        name: 'a b@c.com',
        status: 500,
        code: 'hello world user@example.com',
      );
      expect(
        reporter.pending.single.message,
        'rpc - failed: status=500 code=-',
      );
      reporter.dispose();
    });

    test('the same failing call is deduplicated', () {
      final reporter = _reporter();
      for (var i = 0; i < 50; i++) {
        reporter.noteRequestFailure(
          kind: ErrorKind.rpcError,
          name: 'list_chats',
          status: 500,
        );
      }
      expect(reporter.pendingCount, 1);
      expect(reporter.pending.single.count, 50);
      reporter.dispose();
    });
  });
}

class _Reentrant {
  _Reentrant(this.reporter);

  final ErrorReporter reporter;

  @override
  String toString() {
    // Reporting from inside the work of reporting must not recurse.
    reporter.reportAnomaly(ErrorKind.flutterError, 'nested');
    return 'Reentrant';
  }
}

class _BadToString {
  @override
  String toString() => throw StateError('no string');
}
