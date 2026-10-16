import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/automod_alert_card.dart';
import 'package:wecord/features/circles/circle_automod_repository.dart';
import 'package:wecord/features/circles/circle_automod_screen.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

class FakeRpcDataSource implements RpcDataSource {
  final calls = <({String name, Map<String, dynamic> params})>[];
  final results = <String, Object?>{};

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add((name: functionName, params: params));
    return results[functionName];
  }
}

CircleDetail _detail() {
  final owner = Profile(
    id: 'user-1',
    username: 'ada',
    displayName: 'Ada',
    bio: '',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  return CircleDetail(
    circle: const CircleSummary(
      id: 'circle-1',
      name: 'Book Club',
      memberCount: 1,
      channelCount: 2,
      currentUserRole: 'owner',
      currentUserPermissions: CirclePermission.all,
    ),
    members: [CircleMember(profile: owner, role: 'owner')],
    channels: const [
      CircleChannel(
        id: 'channel-1',
        circleId: 'circle-1',
        conversationId: 'conversation-1',
        name: 'general',
        position: 0,
      ),
      CircleChannel(
        id: 'channel-2',
        circleId: 'circle-1',
        conversationId: 'conversation-2',
        name: 'mod-log',
        position: 1,
      ),
    ],
    posts: const [],
    roles: const [
      CircleRole(
        id: 'role-everyone',
        name: '@everyone',
        position: 0,
        permissions: 0,
        isDefault: true,
      ),
    ],
  );
}

Map<String, dynamic> _keywordRuleJson() => {
  'id': 'rule-1',
  'name': 'Bad words',
  'kind': 'keyword',
  'enabled': true,
  'keywords': ['darn', '*heck*'],
  'regex_patterns': ['fo+bar'],
  'block_message': true,
  'block_reason': 'Keep it clean',
  'alert_channel_id': 'channel-2',
  'timeout_seconds': 60,
  'exempt_role_ids': <String>[],
  'exempt_channel_ids': ['channel-1'],
};

Widget _app(FakeRpcDataSource dataSource, {Widget? home}) {
  return ProviderScope(
    overrides: [
      circleAutoModRepositoryProvider.overrideWithValue(
        CircleAutoModRepository(dataSource),
      ),
    ],
    child: MaterialApp(home: home ?? CircleAutoModScreen(detail: _detail())),
  );
}

void main() {
  test('keywords are split, trimmed, lowered and deduplicated', () {
    expect(parseAutoModKeywords(' Darn, *heck*\nDARN ,, cat* '), [
      'darn',
      '*heck*',
      'cat*',
    ]);
    expect(parseAutoModPatterns('fo+bar\n\n  ba(r|z) '), ['fo+bar', 'ba(r|z)']);
  });

  test('rules read and write the server shape', () {
    final rule = AutoModRule.fromJson(_keywordRuleJson());
    expect(rule.kind, AutoModRuleKind.keyword);
    expect(rule.keywords, ['darn', '*heck*']);
    expect(rule.alertChannelId, 'channel-2');
    expect(rule.toJson(), {
      ..._keywordRuleJson(),
      'mention_limit': null,
      'message_limit': null,
      'window_seconds': null,
    });
    // Without blocking there is no reason to show.
    final draft = AutoModRule.draft(AutoModRuleKind.spam);
    expect(draft.toJson()['id'], isNull);
    expect(draft.toJson().containsKey('id'), isFalse);
    expect(draft.messageLimit, 5);
    expect(draft.windowSeconds, 5);
    expect(
      autoModRuleSummary(rule),
      '2 keywords, 1 patterns · Block message, '
      'Send alert, Time out member',
    );
  });

  test('the repository calls the AutoMod functions', () async {
    final dataSource = FakeRpcDataSource()
      ..results['list_circle_automod_rules'] = [_keywordRuleJson()]
      ..results['save_circle_automod_rule'] = 'rule-2';
    final repository = CircleAutoModRepository(dataSource);

    final rules = await repository.listRules('circle-1');
    expect(rules.single.name, 'Bad words');
    final id = await repository.saveRule(
      circleId: 'circle-1',
      rule: AutoModRule.draft(AutoModRuleKind.mentionSpam),
    );
    expect(id, 'rule-2');
    await repository.deleteRule('rule-1');

    expect(dataSource.calls.map((call) => call.name), [
      'list_circle_automod_rules',
      'save_circle_automod_rule',
      'delete_circle_automod_rule',
    ]);
    expect(dataSource.calls[1].params['target_circle_id'], 'circle-1');
    expect((dataSource.calls[1].params['rule'] as Map)['kind'], 'mention_spam');
    expect(dataSource.calls[2].params, {'target_rule_id': 'rule-1'});
  });

  testWidgets('lists rules by kind and toggles them', (tester) async {
    final dataSource = FakeRpcDataSource()
      ..results['list_circle_automod_rules'] = [_keywordRuleJson()]
      ..results['save_circle_automod_rule'] = 'rule-1';
    await tester.pumpWidget(_app(dataSource));
    await tester.pumpAndSettle();

    expect(find.text('Bad words'), findsOneWidget);
    expect(find.text('Custom keywords'), findsOneWidget);
    expect(find.text('Mention spam'), findsOneWidget);
    expect(find.text('Spam'), findsOneWidget);

    await tester.tap(find.byType(WeCordSwitch).first);
    await tester.pumpAndSettle();

    final save = dataSource.calls.firstWhere(
      (call) => call.name == 'save_circle_automod_rule',
    );
    expect((save.params['rule'] as Map)['enabled'], isFalse);
    expect((save.params['rule'] as Map)['id'], 'rule-1');
  });

  testWidgets('creates a spam rule with a timeout and an alert', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dataSource = FakeRpcDataSource()
      ..results['list_circle_automod_rules'] = <Object>[]
      ..results['save_circle_automod_rule'] = 'rule-9';
    await tester.pumpWidget(_app(dataSource));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('automod-add-spam')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('automod-message-limit')),
      '3',
    );
    await tester.enterText(find.byKey(const ValueKey('automod-window')), '10');
    await tester.tap(find.byKey(const ValueKey('automod-alert')));
    await tester.pumpAndSettle();

    // An alert needs a channel.
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a channel for alerts.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('automod-alert-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#mod-log').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('automod-timeout')));
    await tester.tap(find.byKey(const ValueKey('automod-timeout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    final save = dataSource.calls.lastWhere(
      (call) => call.name == 'save_circle_automod_rule',
    );
    final rule = save.params['rule'] as Map;
    expect(rule['kind'], 'spam');
    expect(rule['message_limit'], 3);
    expect(rule['window_seconds'], 10);
    expect(rule['alert_channel_id'], 'channel-2');
    expect(rule['timeout_seconds'], 60);
    expect(rule['block_message'], isTrue);
    expect(rule.containsKey('id'), isFalse);
    // Back on the list.
    expect(find.byKey(const ValueKey('automod-save')), findsNothing);
  });

  testWidgets('keyword rules need a keyword or a pattern', (tester) async {
    final dataSource = FakeRpcDataSource()
      ..results['list_circle_automod_rules'] = <Object>[];
    await tester.pumpWidget(_app(dataSource));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('automod-add-keyword')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automod-save')));
    await tester.pumpAndSettle();

    expect(find.text('Add a keyword or a pattern.'), findsOneWidget);
    expect(
      dataSource.calls.where((call) => call.name == 'save_circle_automod_rule'),
      isEmpty,
    );
  });

  testWidgets('alerts show who, where, the rule and the message', (
    tester,
  ) async {
    final alert = AutoModAlert.maybeFromJson({
      'kind': 'automod_alert',
      'rule_name': 'Bad words',
      'user_label': 'Grace',
      'channel_name': 'general',
      'content': 'what the heck',
      'matched': '*heck*',
      'blocked': true,
      'timeout_seconds': 300,
    })!;
    expect(AutoModAlert.maybeFromJson({'kind': 'pin'}), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutoModAlertCard(alert: alert)),
      ),
    );

    expect(
      find.text('AutoMod blocked a message from Grace in #general'),
      findsOneWidget,
    );
    expect(find.text('what the heck'), findsOneWidget);
    expect(
      find.text('Rule: Bad words · Matched: *heck* · Timed out for 5 min'),
      findsOneWidget,
    );
  });
}
