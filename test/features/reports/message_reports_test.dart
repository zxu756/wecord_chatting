import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/reports/message_reports.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/report_reason.dart';

import 'report_fakes.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the repository', () {
    test('reports a message with the reporter\'s choices', () async {
      final rpc = FakeReportRpc()..results['report_message'] = 'report-1';
      final repository = MessageReportsRepository(rpc.call);

      await repository.report(
        messageId: 'm1',
        reason: ReportReason.harassment,
        details: '  keeps insulting me  ',
        includeContext: false,
        alsoBlock: true,
      );

      expect(rpc.callsOf('report_message').single, {
        'target_message_id': 'm1',
        'report_reason': 'harassment',
        'report_details': 'keeps insulting me',
        'include_context': false,
        'also_block': true,
      });
    });

    test('shares the context by default and does not block', () async {
      final rpc = FakeReportRpc()..results['report_message'] = 'report-1';
      await MessageReportsRepository(
        rpc.call,
      ).report(messageId: 'm1', reason: ReportReason.spam);
      final params = rpc.callsOf('report_message').single;
      expect(params['include_context'], isTrue);
      expect(params['also_block'], isFalse);
      expect(params['report_details'], '');
    });

    test('lists the open reports of a circle', () async {
      final rpc = FakeReportRpc()
        ..results['list_circle_message_reports'] = [
          circleReportJson(details: 'seen it twice', repeat: 3),
        ];
      final reports = await MessageReportsRepository(
        rpc.call,
      ).listForCircle('circle-1');

      expect(rpc.callsOf('list_circle_message_reports').single, {
        'target_circle_id': 'circle-1',
        'status_filter': 'open',
        'max_results': 100,
      });
      final report = reports.single;
      expect(report.id, 'report-1');
      expect(report.reason, ReportReason.spam);
      expect(report.details, 'seen it twice');
      expect(report.body, 'Win cheap pills at pills.example');
      expect(report.reportedName, 'Eve');
      expect(report.reporterName, 'Dee');
      expect(report.channelName, 'general');
      expect(report.messageAvailable, isTrue);
      expect(report.repeatCount, 3);
      expect(report.context.map((item) => item.senderName), ['Ada', 'Bart']);
      expect(report.context.map((item) => item.isAfter), [false, true]);
    });

    test('a report without context, name or attachment still reads', () {
      final report = CircleMessageReport.fromJson({
        'id': 'r',
        'reason': 'weird',
        'created_at': '2026-10-20T11:30:00Z',
        'snapshot': {
          'body': '',
          'attachment': {
            'kind': 'image',
            'mime_type': 'image/png',
            'name': 'a.png',
          },
        },
      });
      expect(report.reason, ReportReason.other);
      expect(report.context, isEmpty);
      expect(report.reportedUserId, isNull);
      expect(report.attachment, 'Photo · a.png');
      expect(report.messageAvailable, isFalse);
    });

    test('resolves with an action, and a timeout carries its length', () async {
      final rpc = FakeReportRpc()
        ..results['resolve_message_report'] = {'status': 'actioned'};
      final repository = MessageReportsRepository(rpc.call);

      await repository.resolve('report-1', MessageReportAction.dismiss);
      await repository.resolve(
        'report-1',
        MessageReportAction.timeout,
        timeout: const Duration(days: 1),
      );
      await repository.resolve('report-1', MessageReportAction.deleteMessage);
      await repository.resolve('report-1', MessageReportAction.ban);

      expect(rpc.callsOf('resolve_message_report'), [
        {'target_report_id': 'report-1', 'action': 'dismiss'},
        {
          'target_report_id': 'report-1',
          'action': 'timeout',
          'duration_seconds': 86400,
        },
        {'target_report_id': 'report-1', 'action': 'delete_message'},
        {'target_report_id': 'report-1', 'action': 'ban'},
      ]);
    });
  });

  test('the provider reads the circle\'s reports through the RPC', () async {
    final rpc = FakeReportRpc()
      ..results['list_circle_message_reports'] = [circleReportJson()];
    final container = ProviderContainer(overrides: rpc.overrides);
    addTearDown(container.dispose);
    final reports = await container.read(
      circleMessageReportsProvider('circle-1').future,
    );
    expect(reports.single.id, 'report-1');
  });

  group('attachments in a copy', () {
    test('view-once media is only a note', () {
      expect(
        attachmentLabel({'kind': 'view_once', 'view_once': true}),
        'View-once photo or video (not kept)',
      );
    });

    test('are named by kind and file name', () {
      expect(attachmentLabel({'mime_type': 'video/mp4'}), 'Video');
      expect(
        attachmentLabel({'mime_type': 'application/pdf', 'name': 'a.pdf'}),
        'File · a.pdf',
      );
      expect(attachmentLabel({'mime_type': 'audio/aac'}), 'Voice message');
      expect(attachmentLabel(null), isNull);
    });
  });

  test('refusals have their own words', () {
    expect(
      reportFailureText(postgrestError('54000')),
      'You have sent too many reports today. Try again tomorrow.',
    );
    expect(
      reportFailureText(postgrestError('P0002')),
      'This message is no longer available.',
    );
    expect(
      reportFailureText(postgrestError('22023')),
      'This message cannot be reported.',
    );
    expect(
      reportFailureText(StateError('offline')),
      'Could not submit report. Try again.',
    );
    AppStrings.isChinese = true;
    expect(reportFailureText(postgrestError('54000')), '你今天提交的举报太多了，请明天再试。');
  });
}
