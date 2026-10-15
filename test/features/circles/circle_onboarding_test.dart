import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_automod_repository.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

class FakeOnboardingDataSource implements RpcDataSource {
  FakeOnboardingDataSource(this.onboarding);

  Map<String, dynamic> onboarding;
  final calls = <({String name, Map<String, dynamic> params})>[];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add((name: functionName, params: params));
    switch (functionName) {
      case 'get_circle_onboarding':
        return onboarding;
      case 'accept_circle_rules':
        onboarding = {...onboarding, 'needs_acceptance': false};
        return {'welcome_message': onboarding['welcome_message']};
    }
    return null;
  }
}

Widget _app(FakeOnboardingDataSource dataSource, Widget home) {
  return ProviderScope(
    overrides: [
      circleOnboardingRepositoryProvider.overrideWithValue(
        CircleOnboardingRepository(dataSource),
      ),
    ],
    child: MaterialApp(home: home),
  );
}

CircleDetail _detail() {
  return const CircleDetail(
    circle: CircleSummary(
      id: 'circle-1',
      name: 'Book Club',
      memberCount: 1,
      channelCount: 0,
      currentUserRole: 'owner',
      currentUserPermissions: CirclePermission.all,
    ),
    members: [],
    channels: [],
    posts: [],
  );
}

void main() {
  test('onboarding reads the server shape', () {
    final onboarding = CircleOnboarding.fromJson({
      'enabled': true,
      'rules': ['Be kind', 'No spam'],
      'welcome_message': 'Hi!',
      'needs_acceptance': true,
      'accepted_at': null,
    });
    expect(onboarding.enabled, isTrue);
    expect(onboarding.rules, ['Be kind', 'No spam']);
    expect(onboarding.welcomeMessage, 'Hi!');
    expect(onboarding.needsAcceptance, isTrue);
  });

  testWidgets('new members accept the rules, then see the welcome once', (
    tester,
  ) async {
    final dataSource = FakeOnboardingDataSource({
      'enabled': true,
      'rules': ['Be kind', 'No spam'],
      'welcome_message': 'Glad you are here!',
      'needs_acceptance': true,
    });
    await tester.pumpWidget(
      _app(
        dataSource,
        const Scaffold(
          body: CircleOnboardingGate(
            circleId: 'circle-1',
            circleName: 'Book Club',
            child: Text('circle body'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The rules open by themselves, above the circle and its bar.
    expect(find.text('circle body'), findsOneWidget);
    expect(find.byKey(const ValueKey('circle-rules-bar')), findsOneWidget);
    expect(find.text('Rules of Book Club'), findsOneWidget);
    expect(find.text('Be kind'), findsOneWidget);
    final accept = find.byKey(const ValueKey('circle-rules-accept'));
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('circle-rules-agree')));
    await tester.pumpAndSettle();
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(
      dataSource.calls.map((call) => call.name),
      contains('accept_circle_rules'),
    );
    expect(find.text('Welcome to Book Club!'), findsOneWidget);
    expect(find.text('Glad you are here!'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('circle-welcome-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('circle-rules-bar')), findsNothing);
    expect(find.text('circle body'), findsOneWidget);
    expect(find.text('Welcome to Book Club!'), findsNothing);
  });

  testWidgets('members who accepted see the circle as usual', (tester) async {
    final dataSource = FakeOnboardingDataSource({
      'enabled': true,
      'rules': ['Be kind'],
      'needs_acceptance': false,
    });
    await tester.pumpWidget(
      _app(
        dataSource,
        const Scaffold(
          body: CircleOnboardingGate(
            circleId: 'circle-1',
            circleName: 'Book Club',
            child: Text('circle body'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('circle body'), findsOneWidget);
    expect(find.byKey(const ValueKey('circle-rules-bar')), findsNothing);
    expect(find.text('Rules of Book Club'), findsNothing);
  });

  testWidgets('settings save the rules and the welcome message', (
    tester,
  ) async {
    final dataSource = FakeOnboardingDataSource({
      'enabled': false,
      'rules': <String>[],
      'needs_acceptance': false,
    });
    await tester.pumpWidget(
      _app(
        dataSource,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openCircleOnboardingSettings(context, _detail()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('onboarding-enabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-save')));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one rule first.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('onboarding-rule-0')),
      ' Be kind ',
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-add-rule')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-rule-1')),
      'No spam',
    );
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-welcome')),
      'Hello!',
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-save')));
    await tester.pumpAndSettle();

    final save = dataSource.calls.lastWhere(
      (call) => call.name == 'set_circle_onboarding',
    );
    expect(save.params, {
      'target_circle_id': 'circle-1',
      'is_enabled': true,
      'rule_list': ['Be kind', 'No spam'],
      'welcome': 'Hello!',
    });
    expect(find.text('open'), findsOneWidget);
  });
}
