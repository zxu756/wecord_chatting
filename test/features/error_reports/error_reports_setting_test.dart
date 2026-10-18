import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/error_reports/error_report_io.dart';
import 'package:wecord/features/error_reports/error_reporter.dart';
import 'package:wecord/features/error_reports/error_reports_setting.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

Widget _app(ErrorReporter reporter) {
  return ProviderScope(
    overrides: [errorReporterProvider.overrideWithValue(reporter)],
    child: const MaterialApp(home: Scaffold(body: ErrorReportsSettingsGroup())),
  );
}

final _toggle = find.byKey(const ValueKey('error-reports-toggle'));

bool _on(WidgetTester tester) => tester
    .widget<WeCordSwitch>(
      find.descendant(of: _toggle, matching: find.byType(WeCordSwitch)),
    )
    .value;

void main() {
  tearDown(() => AppStrings.isChinese = false);

  testWidgets('is on by default and explains what is sent', (tester) async {
    final reporter = ErrorReporter();
    await reporter.start(store: InMemoryErrorReportStore());
    await tester.pumpWidget(_app(reporter));

    expect(find.text('Send crash and error reports'), findsOneWidget);
    expect(_on(tester), isTrue);
    expect(find.textContaining('never sends your messages'), findsOneWidget);
    expect(find.textContaining('this device only'), findsOneWidget);
    reporter.dispose();
  });

  testWidgets('turning it off stops reports and is kept on the device', (
    tester,
  ) async {
    final store = InMemoryErrorReportStore();
    final reporter = ErrorReporter();
    await reporter.start(store: store);
    reporter.reportAnomaly(ErrorKind.rpcError, 'rpc a failed: status=500');
    expect(reporter.pendingCount, 1);
    await tester.pumpWidget(_app(reporter));

    await tester.tap(_toggle);
    await tester.pump();

    expect(_on(tester), isFalse);
    expect(reporter.enabled, isFalse);
    expect(store.enabled, isFalse);
    expect(reporter.pendingCount, 0, reason: 'what waited is deleted');
    reporter.reportAnomaly(ErrorKind.rpcError, 'rpc b failed: status=500');
    expect(reporter.pendingCount, 0);

    await tester.tap(_toggle);
    await tester.pump();
    expect(_on(tester), isTrue);
    expect(store.enabled, isTrue);
    reporter.reportAnomaly(ErrorKind.rpcError, 'rpc b failed: status=500');
    expect(reporter.pendingCount, 1);
    reporter.dispose();
  });

  testWidgets('shows a device that opted out as off', (tester) async {
    final reporter = ErrorReporter();
    await reporter.start(store: InMemoryErrorReportStore(enabled: false));
    await tester.pumpWidget(_app(reporter));
    expect(_on(tester), isFalse);
    reporter.dispose();
  });

  testWidgets('reads in Chinese', (tester) async {
    AppStrings.isChinese = true;
    final reporter = ErrorReporter();
    await reporter.start(store: InMemoryErrorReportStore());
    await tester.pumpWidget(_app(reporter));
    expect(find.text('发送崩溃和错误报告'), findsOneWidget);
    expect(find.textContaining('绝不会发送你的消息'), findsOneWidget);
    reporter.dispose();
  });
}
