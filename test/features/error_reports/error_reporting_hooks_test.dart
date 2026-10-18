import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/error_reports/anomaly_detectors.dart';
import 'package:wecord/features/error_reports/error_report_io.dart';
import 'package:wecord/features/error_reports/error_reporter.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/features/error_reports/redirect_tracking.dart';

Uri _u(String path) => Uri.parse('https://x.supabase.co$path');

void main() {
  group('classifyRequest', () {
    test('RPC, Edge Function and sign-in calls', () {
      expect(
        classifyRequest(_u('/rest/v1/rpc/list_chats'))?.name,
        'list_chats',
      );
      expect(
        classifyRequest(_u('/rest/v1/rpc/list_chats'))?.kind,
        ErrorKind.rpcError,
      );
      expect(
        classifyRequest(_u('/functions/v1/sessions'))?.kind,
        ErrorKind.functionError,
      );
      expect(
        classifyRequest(_u('/auth/v1/token?grant_type=password'))?.kind,
        ErrorKind.signInError,
      );
      expect(
        classifyRequest(_u('/auth/v1/signup'))?.kind,
        ErrorKind.signInError,
      );
    });

    test('other calls and the report upload itself are not watched', () {
      expect(classifyRequest(_u('/rest/v1/profiles')), isNull);
      expect(classifyRequest(_u('/storage/v1/object/x')), isNull);
      expect(
        classifyRequest(_u('/auth/v1/token?grant_type=refresh_token')),
        isNull,
      );
      expect(classifyRequest(_u('/rest/v1/rpc/report_client_errors')), isNull);
    });
  });

  group('errorCodeOf', () {
    test('reads a PostgREST or Auth code and nothing else', () {
      expect(
        errorCodeOf(utf8.encode('{"code":"42883","message":"secret"}')),
        '42883',
      );
      expect(
        errorCodeOf(utf8.encode('{"error_code":"over_request_rate_limit"}')),
        'over_request_rate_limit',
      );
      expect(errorCodeOf(utf8.encode('not json')), isNull);
      expect(errorCodeOf(utf8.encode('[1]')), isNull);
    });
  });

  group('ErrorReportingHttpClient', () {
    test('passes responses through unchanged and notes failed RPCs', () async {
      final reporter = ErrorReporter();
      final client = ErrorReportingHttpClient(
        MockClient((request) async {
          return http.Response(
            '{"code":"PGRST202","message":"user ada@example.com"}',
            404,
            headers: {'content-type': 'application/json', 'x-a': 'b'},
            request: request,
          );
        }),
        reporter,
      );
      final response = await client.get(_u('/rest/v1/rpc/gone'));
      expect(response.statusCode, 404);
      expect(response.headers['x-a'], 'b');
      expect(response.body, contains('ada@example.com'));
      final report = reporter.pending.single;
      expect(report.message, 'rpc gone failed: status=404 code=PGRST202');
      expect(report.kind, 'rpc_error');
      reporter.dispose();
    });

    test('successful calls and unwatched URLs are not noted', () async {
      final reporter = ErrorReporter();
      final client = ErrorReportingHttpClient(
        MockClient((request) async {
          return request.url.path.endsWith('ok')
              ? http.Response('{}', 200)
              : http.Response('{}', 500);
        }),
        reporter,
      );
      await client.get(_u('/rest/v1/rpc/ok'));
      await client.get(_u('/rest/v1/profiles'));
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });

    test('a failing report upload is never reported', () async {
      final reporter = ErrorReporter();
      final client = ErrorReportingHttpClient(
        MockClient((request) async => http.Response('{}', 500)),
        reporter,
      );
      await client.post(_u('/rest/v1/rpc/report_client_errors'), body: '{}');
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });

    test('a wrong password is not noted, a sign-in outage is', () async {
      final reporter = ErrorReporter();
      var status = 400;
      final client = ErrorReportingHttpClient(
        MockClient(
          (request) async => http.Response(
            '{"error_code":"invalid_credentials","msg":"x@y.com"}',
            status,
          ),
        ),
        reporter,
      );
      final url = _u('/auth/v1/token?grant_type=password');
      await client.post(url, body: 'pw');
      expect(reporter.pendingCount, 0);
      status = 503;
      await client.post(url, body: 'pw');
      expect(reporter.pending.single.kind, 'sign_in_error');
      reporter.dispose();
    });

    test('network failures reach the app untouched', () async {
      final reporter = ErrorReporter();
      final client = ErrorReportingHttpClient(
        MockClient((request) async => throw http.ClientException('offline')),
        reporter,
      );
      await expectLater(
        client.get(_u('/rest/v1/rpc/x')),
        throwsA(isA<http.ClientException>()),
      );
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });
  });

  group('SupabaseErrorReportSink', () {
    SupabaseClient clientFor(http.Client mock) =>
        SupabaseClient('https://x.supabase.co', 'key', httpClient: mock);

    test('calls report_client_errors with the reports', () async {
      http.Request? seen;
      final sink = SupabaseErrorReportSink(
        () => clientFor(
          MockClient((request) async {
            seen = request;
            return http.Response(
              '{"accepted":1,"dropped":0}',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        ),
      );
      await sink.send([
        {'kind': 'flutter_error', 'fingerprint': 'abcdef0123456789'},
      ]);
      expect(seen!.url.path, '/rest/v1/rpc/report_client_errors');
      final body = jsonDecode(seen!.body) as Map;
      expect(body['reports'], hasLength(1));
    });

    test('a database refusal is final, a gateway failure is not', () async {
      Future<Object?> outcome(String body, int status) async {
        final sink = SupabaseErrorReportSink(
          () => clientFor(
            MockClient(
              (request) async => http.Response(
                body,
                status,
                headers: {'content-type': 'application/json'},
                request: request,
              ),
            ),
          ),
        );
        try {
          await sink.send(const []);
          return null;
        } on Object catch (error) {
          return error;
        }
      }

      expect(
        await outcome('{"code":"42501","message":"denied"}', 403),
        isA<ErrorReportRejected>(),
      );
      expect(
        await outcome('{"message":"bad gateway"}', 502),
        isNot(isA<ErrorReportRejected>()),
      );
    });
  });

  group('error hooks', () {
    late FlutterExceptionHandler? savedFlutter;
    late ErrorCallback? savedPlatform;

    setUp(() {
      savedFlutter = FlutterError.onError;
      savedPlatform = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = savedFlutter;
      PlatformDispatcher.instance.onError = savedPlatform;
    });

    test('framework and platform errors are reported', () {
      final reporter = ErrorReporter();
      var printed = 0;
      FlutterError.onError = (details) => printed++;
      installErrorHooks(reporter);

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('framework'),
          stack: StackTrace.current,
        ),
      );
      final handled = PlatformDispatcher.instance.onError!(
        ArgumentError('platform'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(printed, 1, reason: 'the previous handler still runs');
      expect(reporter.pending.map((r) => r.kind), [
        'flutter_error',
        'platform_error',
      ]);
      reporter.dispose();
    });

    test('uncaught zone errors are reported', () async {
      final reporter = ErrorReporter();
      await runReportingErrors(reporter, () async {
        unawaited(Future<void>.error(StateError('in the zone')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(reporter.pending.single.kind, 'zone_error');
      reporter.dispose();
    });

    test('an error thrown by the body itself is reported too', () async {
      final reporter = ErrorReporter();
      await runReportingErrors(reporter, () async {
        throw StateError('startup failed');
      });
      expect(reporter.pending.single.kind, 'zone_error');
      reporter.dispose();
    });
  });

  group('ErrorReportingProviderObserver', () {
    test('reports failing providers, not rebuilds or network errors', () async {
      final reporter = ErrorReporter();
      final failing = FutureProvider<int>((ref) => throw StateError('nope'));
      final offline = FutureProvider<int>(
        (ref) => throw http.ClientException('offline'),
      );
      final fine = StateProvider0();
      final container = ProviderContainer(
        retry: (_, _) => null,
        observers: [ErrorReportingProviderObserver(reporter)],
      );
      addTearDown(container.dispose);

      container.read(fine.provider);
      container.read(fine.provider);
      container.invalidate(fine.provider);
      container.read(fine.provider);
      expect(reporter.pendingCount, 0);

      await expectLater(container.read(offline.future), throwsA(anything));
      expect(reporter.pendingCount, 0);

      await expectLater(container.read(failing.future), throwsA(anything));
      expect(reporter.pending.single.kind, 'provider_error');
      reporter.dispose();
    });
  });

  group('trackRedirects', () {
    testWidgets('a flapping sign-in state is reported as a redirect loop', (
      tester,
    ) async {
      final reporter = ErrorReporter(
        redirectLoops: RedirectLoopDetector(threshold: 3),
      );
      final flap = ValueNotifier<bool>(true);
      final router = GoRouter(
        initialLocation: '/home',
        refreshListenable: flap,
        redirect: trackRedirects(reporter, (context, state) {
          final signedIn = flap.value;
          if (state.uri.path == '/home') {
            return signedIn ? null : '/auth';
          }
          return signedIn ? '/home' : null;
        }),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(path: '/auth', builder: (_, _) => const Text('auth')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(reporter.pendingCount, 0);
      for (var i = 0; i < 12; i++) {
        flap.value = !flap.value;
        await tester.pump();
      }
      final loop = reporter.pending.where(
        (r) => r.kind == 'router_redirect_loop',
      );
      expect(loop, isNotEmpty);
      expect(loop.first.message, contains('/home'));
      reporter.dispose();
    });

    testWidgets('redirects pass through unchanged', (tester) async {
      final reporter = ErrorReporter();
      final router = GoRouter(
        initialLocation: '/start',
        redirect: trackRedirects(
          reporter,
          (context, state) => state.uri.path == '/start' ? '/home' : null,
        ),
        routes: [
          GoRoute(path: '/start', builder: (_, _) => const Text('start')),
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('home'), findsOneWidget);
      expect(reporter.pendingCount, 0);
      reporter.dispose();
    });
  });
}

/// A provider that exists only to be rebuilt.
class StateProvider0 {
  final provider = Provider<int>((ref) => 1);
}
