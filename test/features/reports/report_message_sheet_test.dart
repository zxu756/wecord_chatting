import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_builtin.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/features/reports/report_message_action.dart';
import 'package:wecord/features/reports/report_message_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../legal/legal_test_support.dart';
import 'report_fakes.dart';

/// A page with a button that opens the report sheet; [result] collects what
/// the sheet pops with.
Future<void> _open(
  WidgetTester tester,
  FakeReportRpc rpc, {
  String? circleId,
  List<bool?>? result,
}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: rpc.overrides,
      child: DefaultAssetBundle(
        bundle: DiskAssetBundle(),
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final sent = await showReportMessageSheet(
                      context,
                      message: otherMessage(),
                      senderName: 'Eve',
                      circleId: circleId,
                    );
                    result?.add(sent);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

bool _switch(WidgetTester tester, String key) => tester
    .widget<WeCordSwitch>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(WeCordSwitch),
      ),
    )
    .value;

void main() {
  tearDown(() => AppStrings.isChinese = false);

  testWidgets('offers the reasons, the details, the two switches and a link', (
    tester,
  ) async {
    await _open(tester, FakeReportRpc());

    expect(find.text('Report message'), findsOneWidget);
    for (final reason in [
      'Spam',
      'Harassment',
      'Impersonation',
      'Unsafe content',
      'Other',
    ]) {
      expect(find.text(reason), findsOneWidget, reason: reason);
    }
    expect(find.byKey(const ValueKey('report-details')), findsOneWidget);
    expect(find.text('Include context'), findsOneWidget);
    expect(
      find.textContaining('Shares up to 5 messages before and after it'),
      findsOneWidget,
    );
    expect(find.text('Also block Eve'), findsOneWidget);
    expect(find.text('Read the Community Guidelines'), findsOneWidget);
    // Context is on, blocking is off, until the reporter says otherwise.
    expect(_switch(tester, 'report-include-context'), isTrue);
    expect(_switch(tester, 'report-also-block'), isFalse);
  });

  testWidgets('says who receives the report', (tester) async {
    await _open(tester, FakeReportRpc());
    expect(
      find.textContaining('This goes to the WeCord team.'),
      findsOneWidget,
    );
  });

  testWidgets('a circle report goes to its moderators', (tester) async {
    await _open(tester, FakeReportRpc(), circleId: 'circle-1');
    expect(
      find.textContaining("This goes to this circle's moderators."),
      findsOneWidget,
    );
  });

  testWidgets('sends the chosen reason, details and switches', (tester) async {
    final rpc = FakeReportRpc()..results['report_message'] = 'report-1';
    final result = <bool?>[];
    await _open(tester, rpc, result: result);

    await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('report-details')),
      'keeps insulting me',
    );
    await tester.tap(find.byKey(const ValueKey('report-include-context')));
    await tester.tap(find.byKey(const ValueKey('report-also-block')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await tester.pumpAndSettle();

    expect(rpc.callsOf('report_message').single, {
      'target_message_id': 'm1',
      'report_reason': 'harassment',
      'report_details': 'keeps insulting me',
      'include_context': false,
      'also_block': true,
    });
    expect(result, [true]);
    expect(find.text('Report message'), findsNothing);
  });

  testWidgets('keeps the sheet open and says why when the server refuses', (
    tester,
  ) async {
    final rpc = FakeReportRpc()
      ..failing['report_message'] = postgrestError('54000');
    final result = <bool?>[];
    await _open(tester, rpc, result: result);

    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('You have sent too many reports today. Try again tomorrow.'),
      findsOneWidget,
    );
    expect(result, isEmpty);
    // It can be sent again.
    expect(find.text('Submit report'), findsOneWidget);
  });

  testWidgets('links to the community guidelines', (tester) async {
    await _open(tester, FakeReportRpc());
    await tester.ensureVisible(
      find.byKey(const ValueKey('report-guidelines-link')),
    );
    await tester.tap(find.byKey(const ValueKey('report-guidelines-link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('legal-guidelines')), findsOneWidget);
    expect(find.text('Community Guidelines'), findsWidgets);
  });

  testWidgets('reads in Chinese', (tester) async {
    AppStrings.isChinese = true;
    await _open(tester, FakeReportRpc());
    expect(find.text('举报消息'), findsOneWidget);
    expect(find.text('同时拉黑 Eve'), findsOneWidget);
    expect(find.text('附带上下文'), findsOneWidget);
  });

  group('the menu entry', () {
    Future<List<String>> labels(
      WidgetTester tester, {
      bool own = false,
      ChatMessage? message,
      String? circleId,
      bool pending = false,
    }) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final ctx = MessageActionContext(
        context: captured,
        message: pending
            ? otherMessage(id: 'outbox:abc')
            : message ?? otherMessage(),
        isCurrentUser: own,
        canCompose: true,
        canPin: false,
        canStartThread: false,
        canModerate: false,
        isSaved: false,
        circleId: circleId,
        previewUrl: null,
        onReply: (_) {},
        onEdit: (_) {},
        onForward: (_) {},
        onDelete: (_) async {},
        onPreviewImage: (_) async {},
        onTogglePin: (_) async {},
        onRemoveEmbed: (_) async {},
      );
      return [
        for (final action in reportMessageAction.build(ctx)) action.label,
      ];
    }

    testWidgets('is there for other people\'s messages', (tester) async {
      expect(await labels(tester), ['Report']);
      expect(await labels(tester, circleId: 'circle-1'), ['Report']);
    });

    testWidgets('is not there for your own messages', (tester) async {
      expect(await labels(tester, own: true), isEmpty);
    });

    testWidgets('is not there for deleted messages or system notices', (
      tester,
    ) async {
      expect(
        await labels(
          tester,
          message: otherMessage(recalledAt: DateTime.utc(2026, 10, 20)),
        ),
        isEmpty,
      );
      expect(
        await labels(tester, message: otherMessage(type: MessageType.system)),
        isEmpty,
      );
    });

    testWidgets('is not there while the message is still being sent', (
      tester,
    ) async {
      expect(await labels(tester, pending: true), isEmpty);
    });

    test('is registered in the menu between Remove embed and Delete', () {
      final ids = MessageActionRegistry([
        ...builtInMessageActions,
        ...messageActionExtensions,
      ]).ids;
      expect(ids.indexOf('report'), ids.indexOf('remove-embed') + 1);
      expect(ids.indexOf('delete'), ids.indexOf('report') + 1);
    });
  });
}
