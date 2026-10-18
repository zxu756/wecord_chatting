import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/error_reports/error_scrubber.dart';

/// What an error is called in a report: its type and a message that has been
/// through [ErrorScrubber]. Errors from the backend are described by their
/// codes only; the message text of a server error is never kept.
class ErrorDescription {
  const ErrorDescription(this.type, this.message);

  final String type;
  final String message;
}

/// A failure to reach the network: not a bug in the app, and noise in
/// reports.
bool isNetworkError(Object error) {
  final inner = error is ProviderException ? error.exception : error;
  // dart:io is not there on the web, so the sockets are told by name.
  final name = '${inner.runtimeType}';
  return name == 'SocketException' ||
      name == 'HandshakeException' ||
      inner is TimeoutException ||
      inner is http.ClientException ||
      inner is AuthRetryableFetchException;
}

ErrorDescription describeError(Object error) {
  final inner = error is ProviderException ? error.exception : error;
  try {
    if (inner is PostgrestException) {
      final message = ErrorScrubber.message(inner.message);
      return ErrorDescription(
        'PostgrestException',
        'code=${_code(inner.code)} $message'.trim(),
      );
    }
    if (inner is AuthException) {
      return ErrorDescription(
        '${inner.runtimeType}',
        'status=${_code(inner.statusCode)} code=${_code(_authCode(inner))}',
      );
    }
    if (inner is FunctionException) {
      return ErrorDescription('FunctionException', 'status=${inner.status}');
    }
    if (isNetworkError(inner)) {
      return ErrorDescription('${inner.runtimeType}', '');
    }
    if (inner is FormatException) {
      return ErrorDescription(
        'FormatException',
        ErrorScrubber.message(inner.message),
      );
    }
    return ErrorDescription(
      '${inner.runtimeType}',
      ErrorScrubber.message('$inner'),
    );
  } on Object {
    // Describing must never fail.
    return ErrorDescription('${inner.runtimeType}', '');
  }
}

String? _authCode(AuthException error) {
  return error is AuthApiException ? error.code : null;
}

/// An error code kept only when it looks like one.
String _code(String? code) {
  if (code != null && RegExp(r'^[A-Za-z0-9_.\-]{1,40}$').hasMatch(code)) {
    return code;
  }
  return '-';
}
