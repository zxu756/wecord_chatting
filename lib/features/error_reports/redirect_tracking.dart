import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/error_reports/error_reporter.dart';

/// Wraps a router's redirect so every redirect it makes is noted (a loop
/// then shows up as a report). The answer of [inner] is returned as it is.
FutureOr<String?> Function(BuildContext, GoRouterState) trackRedirects(
  ErrorReporter reporter,
  FutureOr<String?> Function(BuildContext, GoRouterState) inner,
) {
  return (context, state) {
    final result = inner(context, state);
    if (result is String) {
      reporter.noteRedirect(state.uri.path, Uri.parse(result).path);
    }
    return result;
  };
}
