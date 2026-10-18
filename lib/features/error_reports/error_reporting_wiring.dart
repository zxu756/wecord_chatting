import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/error_reports/error_reporter.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/features/error_reports/error_scrubber.dart';
import 'package:wecord/shared/navigation/app_router.dart';

/// Wires the reporter to the running app: route changes become breadcrumbs,
/// and so do app lifecycle changes. The app watches this once.
final errorReportingWiringProvider = Provider<void>((ref) {
  attachErrorReporting(
    ref.watch(appRouterProvider),
    errorReporter,
    ref.onDispose,
  );
});

/// The part of the wiring that does not need Riverpod; [onDispose] is told
/// how to undo it.
void attachErrorReporting(
  GoRouter router,
  ErrorReporter reporter,
  void Function(void Function()) onDispose,
) {
  var lastRoute = '';
  String template() {
    try {
      return router.routerDelegate.currentConfiguration.fullPath;
    } on Object {
      return '';
    }
  }

  void onRoute() {
    final now = template();
    if (now.isNotEmpty && now != lastRoute) {
      lastRoute = now;
      reporter.noteRoute(now);
    }
  }

  reporter.routeProvider = () => ErrorScrubber.route(lastRoute);
  router.routerDelegate.addListener(onRoute);
  onRoute();
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) => reporter.noteLifecycle(state.name),
  );
  onDispose(() {
    router.routerDelegate.removeListener(onRoute);
    lifecycle.dispose();
    reporter.routeProvider = null;
  });
}
