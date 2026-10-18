import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What kind of problem a report is about. The names are the ones the
/// database accepts (`report_client_errors`).
enum ErrorKind {
  flutterError('flutter_error'),
  platformError('platform_error'),
  zoneError('zone_error'),
  providerError('provider_error'),
  unexpectedSignOut('auth_unexpected_sign_out'),
  refreshBurst('auth_refresh_burst'),
  redirectLoop('router_redirect_loop'),
  rpcError('rpc_error'),
  functionError('function_error'),
  signInError('sign_in_error');

  const ErrorKind(this.wire);

  final String wire;
}

/// One report, possibly standing for several identical problems ([count]).
class ErrorReport {
  ErrorReport({
    required this.kind,
    required this.message,
    required this.stack,
    required this.fingerprint,
    required this.platform,
    required this.appVersion,
    required this.build,
    required this.context,
    this.count = 1,
    this.notBefore,
  });

  factory ErrorReport.fromJson(Map<String, Object?> json) {
    return ErrorReport(
      kind: json['kind'] as String,
      message: json['message'] as String? ?? '',
      stack: json['stack'] as String? ?? '',
      fingerprint: json['fingerprint'] as String,
      platform: json['platform'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      build: json['build'] as String? ?? '',
      context: Map<String, Object?>.from(json['context'] as Map? ?? const {}),
      count: json['count'] as int? ?? 1,
    );
  }

  final String kind;
  final String message;
  final String stack;
  final String fingerprint;
  final String platform;
  final String appVersion;
  final String build;
  final Map<String, Object?> context;
  int count;

  /// Not sent before this time (the same problem was sent a moment ago).
  /// Not stored.
  DateTime? notBefore;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'message': message,
    'stack': stack,
    'fingerprint': fingerprint,
    'platform': platform,
    'app_version': appVersion,
    'build': build,
    'context': context,
    'count': count,
  };
}

/// Where the device keeps its report setting and the queue of reports not
/// sent yet; tests swap in memory.
abstract interface class ErrorReportStore {
  Future<bool?> loadEnabled();

  Future<void> saveEnabled(bool enabled);

  Future<List<Map<String, Object?>>> loadQueue();

  Future<void> saveQueue(List<Map<String, Object?>> queue);
}

const errorReportsEnabledKey = 'wecord.error_reports.enabled';
const errorReportsQueueKey = 'wecord.error_reports.queue';

class SharedPreferencesErrorReportStore implements ErrorReportStore {
  const SharedPreferencesErrorReportStore();

  @override
  Future<bool?> loadEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(errorReportsEnabledKey);
  }

  @override
  Future<void> saveEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(errorReportsEnabledKey, enabled);
  }

  @override
  Future<List<Map<String, Object?>>> loadQueue() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(errorReportsQueueKey);
    if (raw == null) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    return [
      if (decoded is List)
        for (final item in decoded)
          if (item is Map) Map<String, Object?>.from(item),
    ];
  }

  @override
  Future<void> saveQueue(List<Map<String, Object?>> queue) async {
    final preferences = await SharedPreferences.getInstance();
    if (queue.isEmpty) {
      await preferences.remove(errorReportsQueueKey);
    } else {
      await preferences.setString(errorReportsQueueKey, jsonEncode(queue));
    }
  }
}

class InMemoryErrorReportStore implements ErrorReportStore {
  InMemoryErrorReportStore({this.enabled, List<Map<String, Object?>>? queue})
    : queue = queue ?? [];

  bool? enabled;
  List<Map<String, Object?>> queue;

  @override
  Future<bool?> loadEnabled() async => enabled;

  @override
  Future<void> saveEnabled(bool value) async => enabled = value;

  @override
  Future<List<Map<String, Object?>>> loadQueue() async => queue;

  @override
  Future<void> saveQueue(List<Map<String, Object?>> value) async {
    queue = [for (final item in value) Map<String, Object?>.from(item)];
  }
}

/// Sends a batch of reports to the server.
abstract interface class ErrorReportSink {
  /// Throws [ErrorReportRejected] when the server refused the batch for good
  /// (do not send it again), anything else when it may work later.
  Future<void> send(List<Map<String, Object?>> reports);
}

class ErrorReportRejected implements Exception {
  const ErrorReportRejected();
}

/// Calls the `report_client_errors` function. The client is looked up on
/// each send, so reports wait quietly until Supabase is ready.
class SupabaseErrorReportSink implements ErrorReportSink {
  const SupabaseErrorReportSink(this._client);

  /// The name of the function; the HTTP observer skips it so a failing
  /// report is never reported.
  static const functionName = 'report_client_errors';

  final SupabaseClient Function() _client;

  @override
  Future<void> send(List<Map<String, Object?>> reports) async {
    try {
      await _client().rpc<dynamic>(functionName, params: {'reports': reports});
    } on PostgrestException catch (error) {
      // A database or PostgREST code means the server looked at the batch
      // and refused it; a bare HTTP status (a gateway down) may pass later.
      if (RegExp(r'^(PGRST\d+|[0-9A-Z]{5})$').hasMatch(error.code ?? '')) {
        throw const ErrorReportRejected();
      }
      rethrow;
    }
  }
}
