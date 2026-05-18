import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/report_user_sheet.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  testWidgets('report sheet submits selected reason and details', (
    tester,
  ) async {
    final dataSource = FakeProfileDataSource();
    final repository = ProfileRepository.withDataSource(dataSource);

    await tester.pumpWidget(buildReportHarness(repository: repository));
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spam'));
    await tester.enterText(find.byType(TextField), 'Repeated spam invites');
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(dataSource.reportedTargetUserId, adaProfile.id);
    expect(dataSource.reportedReason, ReportReason.spam);
    expect(dataSource.reportedDetails, 'Repeated spam invites');
    expect(find.text('Submit report'), findsNothing);
  });

  testWidgets('report sheet shows every reason and defaults to spam', (
    tester,
  ) async {
    final dataSource = FakeProfileDataSource();
    final repository = ProfileRepository.withDataSource(dataSource);

    await tester.pumpWidget(buildReportHarness(repository: repository));
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    for (final reason in ReportReason.values) {
      expect(find.text(reason.label), findsOneWidget);
    }

    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(dataSource.reportedReason, ReportReason.spam);
    expect(dataSource.reportedDetails, '');
  });

  testWidgets('report sheet caps details at 1000 characters', (tester) async {
    final dataSource = FakeProfileDataSource();
    final repository = ProfileRepository.withDataSource(dataSource);
    final longDetails = 'a' * 1001;

    await tester.pumpWidget(buildReportHarness(repository: repository));
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), longDetails);
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(dataSource.reportedDetails, 'a' * 1000);
  });

  testWidgets('report sheet keeps open and shows failure text on error', (
    tester,
  ) async {
    final dataSource = FakeProfileDataSource()
      ..reportError = Exception('network failed');
    final repository = ProfileRepository.withDataSource(dataSource);

    await tester.pumpWidget(buildReportHarness(repository: repository));
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(find.text('Could not submit report. Try again.'), findsWidgets);
    expect(find.text('Submit report'), findsOneWidget);
  });
}

Widget buildReportHarness({required ProfileRepository repository}) {
  return ProviderScope(
    overrides: [profileRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: FilledButton(
                onPressed: () => showReportUserSheet(context, adaProfile),
                child: const Text('Report'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

final adaProfile = Profile(
  id: 'user-2',
  username: 'ada',
  displayName: 'Ada Lovelace',
  bio: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class FakeProfileDataSource implements ProfileDataSource {
  Object? reportError;
  String? reportedTargetUserId;
  ReportReason? reportedReason;
  String? reportedDetails;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    if (functionName != 'report_user') {
      throw StateError('Unexpected RPC: $functionName');
    }
    final error = reportError;
    if (error != null) {
      throw error;
    }
    reportedTargetUserId = params['target_user_id'] as String;
    reportedReason = ReportReason.values.singleWhere(
      (reason) => reason.value == params['report_reason'],
    );
    reportedDetails = params['report_details'] as String;
    return null;
  }
}
