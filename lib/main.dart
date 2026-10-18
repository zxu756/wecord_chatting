import 'package:flutter/widgets.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';

Future<void> main() async {
  // Uncaught errors (framework, platform and zone) go to the error reports.
  installErrorHooks(errorReporter);
  await runReportingErrors(errorReporter, () async {
    WidgetsFlutterBinding.ensureInitialized();
    await runWeCordApp();
  });
}
