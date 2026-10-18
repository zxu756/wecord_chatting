import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderObserver, ProviderObserverContext;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/error_reports/error_description.dart';
import 'package:wecord/features/error_reports/error_report_io.dart';
import 'package:wecord/features/error_reports/error_reporter.dart';
import 'package:wecord/features/privacy/device_info.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The one reporter of the app. Hooks are installed before the widget tree
/// exists, so it lives here and not in a provider; tests build their own
/// [ErrorReporter] and never touch this one's sink.
final ErrorReporter errorReporter = ErrorReporter(
  environment: ReporterEnvironment(
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
    appVersion: appVersion,
    build: const String.fromEnvironment('APP_BUILD'),
  ),
);

/// Starts reporting: the device's saved setting and queue are loaded and
/// uploads go to the server. Safe to call once, early.
Future<void> startErrorReporting() async {
  errorReporter.localeProvider = () => AppStrings.isChinese ? 'zh' : 'en';
  await errorReporter.start(
    sink: SupabaseErrorReportSink(() => Supabase.instance.client),
    store: const SharedPreferencesErrorReportStore(),
  );
}

/// Captures what the framework, the platform and the zone report as
/// uncaught. Call before the app starts.
void installErrorHooks(ErrorReporter reporter) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    // Keep what the app did before (printing in the console).
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
    reporter.report(ErrorKind.flutterError, details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reporter.report(ErrorKind.platformError, error, stack);
    if (kDebugMode) {
      debugPrint('Uncaught error: $error\n$stack');
    }
    return true;
  };
}

/// Runs [body] in a zone whose uncaught errors are reported.
Future<void> runReportingErrors(
  ErrorReporter reporter,
  Future<void> Function() body,
) async {
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await body();
      } finally {
        if (!done.isCompleted) {
          done.complete();
        }
      }
    },
    (error, stack) {
      reporter.report(ErrorKind.zoneError, error, stack);
      if (kDebugMode) {
        debugPrint('Uncaught zone error: $error\n$stack');
      }
    },
  );
  await done.future;
}

/// Reports providers that fail (only failures, not rebuilds). Network
/// failures are left out: they say nothing about the app.
base class ErrorReportingProviderObserver extends ProviderObserver {
  ErrorReportingProviderObserver(this._reporter);

  final ErrorReporter _reporter;

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      if (isNetworkError(error)) {
        return;
      }
      final provider = context.provider;
      _reporter.report(
        ErrorKind.providerError,
        error,
        stackTrace,
        discriminator: provider.name ?? '${provider.runtimeType}',
      );
    } on Object {
      // Never throws.
    }
  }
}

/// Wraps the HTTP client of Supabase to notice RPC, Edge Function and
/// sign-in calls that fail. It reads only the status and the error code of a
/// failed response (never request bodies, headers or message text), passes
/// everything through unchanged, and cannot fail a request itself.
class ErrorReportingHttpClient extends http.BaseClient {
  ErrorReportingHttpClient(this._inner, this._reporter);

  final http.Client _inner;
  final ErrorReporter _reporter;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode < 400) {
      return response;
    }
    try {
      final target = classifyRequest(request.url);
      if (target == null) {
        return response;
      }
      final length = response.contentLength;
      if (length != null && length > 65536) {
        _note(target, response.statusCode, null);
        return response;
      }
      final bytes = await response.stream.toBytes();
      _note(target, response.statusCode, errorCodeOf(bytes));
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on Object {
      // The observer never changes what the app gets. If the body could
      // not be read, the request fails the way it would have anyway.
      return response;
    }
  }

  void _note(RequestTarget target, int status, String? code) {
    _reporter.noteRequestFailure(
      kind: target.kind,
      name: target.name,
      status: status,
      code: code,
    );
  }

  @override
  void close() => _inner.close();
}

/// What a request is, for reports.
class RequestTarget {
  const RequestTarget(this.kind, this.name);

  final ErrorKind kind;
  final String name;
}

/// An RPC (`/rest/v1/rpc/<name>`), an Edge Function (`/functions/v1/<name>`)
/// or a sign-in call (`/auth/v1/token`, `/auth/v1/signup`); null for
/// anything else, and for the report upload itself, so a failing upload is
/// never reported.
RequestTarget? classifyRequest(Uri url) {
  final segments = url.pathSegments;
  for (var i = 0; i + 2 < segments.length; i++) {
    final scope = segments[i];
    final version = segments[i + 1];
    final name = segments[i + 2];
    if (scope == 'rest' && version == 'v1' && name == 'rpc') {
      if (i + 3 >= segments.length ||
          segments[i + 3] == SupabaseErrorReportSink.functionName) {
        return null;
      }
      return RequestTarget(ErrorKind.rpcError, segments[i + 3]);
    }
    if (scope == 'functions' && version == 'v1') {
      return RequestTarget(ErrorKind.functionError, name);
    }
    if (scope == 'auth' &&
        version == 'v1' &&
        (name == 'token' || name == 'signup')) {
      final grant = url.queryParameters['grant_type'];
      // A refresh that fails is the auth anomaly detectors' business.
      if (name == 'token' && grant != 'password') {
        return null;
      }
      return RequestTarget(ErrorKind.signInError, name);
    }
  }
  return null;
}

/// The `code` (PostgREST) or `error_code` (Auth) of an error body, if it is
/// there and short; nothing else of the body is read.
String? errorCodeOf(List<int> body) {
  try {
    final json = jsonDecode(utf8.decode(body, allowMalformed: true));
    if (json is Map) {
      final code = json['code'] ?? json['error_code'];
      if (code is String || code is int) {
        return '$code';
      }
    }
  } on Object {
    // Not JSON.
  }
  return null;
}

/// Watches Supabase auth events (breadcrumbs, refresh bursts, sign-outs
/// nobody asked for). Returns the subscription so it can be cancelled.
StreamSubscription<AuthState> watchAuthEvents(
  GoTrueClient auth,
  ErrorReporter reporter,
) {
  return auth.onAuthStateChange.listen(
    (state) => reporter.noteAuthEvent(state.event.name),
    onError: (Object _) {},
  );
}
