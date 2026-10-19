import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/onboarding/guide_editor_screen.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/features/circles/onboarding/newcomer_card.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart'
    show PhoneWorld, circleDetail, notchedPhone, settle, usePhoneViewport;
import 'circle_onboarding_test.dart' show FakeOnboardingDataSource;
import 'onboarding_guide_fakes.dart';

const _channels = [
  CircleChannel(
    id: 'ch-general',
    circleId: 'circle-1',
    conversationId: 'conv-general',
    name: 'general',
    position: 0,
  ),
  CircleChannel(
    id: 'ch-games',
    circleId: 'circle-1',
    conversationId: 'conv-games',
    name: 'games',
    position: 1,
  ),
];

/// A member who needs nothing from the rules.
FakeOnboardingDataSource _rules() => FakeOnboardingDataSource({
  'enabled': false,
  'rules': <String>[],
  'needs_acceptance': false,
});

Widget _gate(GuideRpc rpc, {FakeOnboardingDataSource? rules}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: CircleOnboardingGate(
            circleId: 'circle-1',
            circleName: 'Book Club',
            channels: _channels,
            child: Text('circle body'),
          ),
        ),
      ),
      GoRoute(
        path: '/circles/:circleId/channels/:conversationId',
        builder: (context, state) => Scaffold(
          body: Text('opened ${state.pathParameters['conversationId']}'),
        ),
      ),
    ],
  );
  return ProviderScope(
    retry: noProviderRetry,
    overrides: [
      circleRpcProvider.overrideWithValue(rpc.call),
      circleOnboardingRepositoryProvider.overrideWithValue(
        CircleOnboardingRepository(rules ?? _rules()),
      ),
    ],
    child: MaterialApp.router(theme: WeCordTheme.light(), routerConfig: router),
  );
}

class _SignedIn implements AuthRepository {
  _SignedIn(this.id);

  final String id;

  @override
  AuthUser? get currentUser => AuthUser(id: id);

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(AuthUser(id: id));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Chats implements ChatsRepository {
  final stickers = <({String conversationId, String stickerId})>[];
  final texts = <({String conversationId, String body})>[];
  var stickerFails = false;
  var textFails = false;

  @override
  Future<void> sendSticker({
    required String conversationId,
    required String stickerId,
  }) async {
    if (stickerFails) {
      throw StateError('no sticker');
    }
    stickers.add((conversationId: conversationId, stickerId: stickerId));
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {
    if (textFails) {
      throw StateError('no text');
    }
    texts.add((conversationId: conversationId, body: body));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _card(_Chats chats, NewcomerNotice notice, {String me = 'user-1'}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(chats),
      authRepositoryProvider.overrideWithValue(_SignedIn(me)),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(
        body: NewcomerCard(conversationId: 'conv-welcome', notice: notice),
      ),
    ),
  );
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the guide as the server sends it', () {
    test('questions, tasks and progress parse', () {
      final guide = CircleGuide.fromJson(guideJson());
      expect(guide.enabled, isTrue);
      expect(
        guide.prompts.single.options.first.roles.single.name,
        'Photographers',
      );
      expect(guide.prompts.single.options.first.channels.single.name, 'games');
      expect(guide.tasks.map((task) => task.action), [
        GuideTaskAction.readRules,
        GuideTaskAction.visitChannel,
        GuideTaskAction.setAvatar,
      ]);
      expect(guide.doneCount, 1);
      expect(guide.taskCount, 3);
      expect(guide.tasksComplete, isFalse);
    });

    test('the card shows only to new members with something left', () {
      expect(CircleGuide.fromJson(guideJson()).showsCard, isTrue);
      expect(
        CircleGuide.fromJson(guideJson(newMember: false)).showsCard,
        isFalse,
        reason: 'members from before the guide find it in the menu',
      );
      expect(
        CircleGuide.fromJson(guideJson(dismissed: true)).showsCard,
        isFalse,
      );
      expect(
        CircleGuide.fromJson(
          guideJson(prompts: [], tasks: [guideTaskJson(done: true)]),
        ).showsCard,
        isFalse,
        reason: 'all done',
      );
      expect(
        CircleGuide.fromJson(
          guideJson(tasks: [guideTaskJson(done: true)]),
        ).showsCard,
        isTrue,
        reason: 'the questions are still open',
      );
      expect(
        CircleGuide.fromJson(
          guideJson(tasks: [guideTaskJson(done: true)], answered: true),
        ).showsCard,
        isFalse,
      );
      expect(CircleGuide.fromJson({'enabled': false}).showsCard, isFalse);
    });

    test('an unknown task kind reads as sending a message', () {
      expect(GuideTaskAction.fromJson('later'), GuideTaskAction.sendMessage);
    });

    test('the editor drafts write what the server reads', () {
      final config = CircleGuideConfig.fromJson(guideConfigJson());
      expect(config.assignableRoleIds, {'role-photo'});
      final json = config.prompts.single.toJson();
      expect(json['id'], 'prompt-1');
      expect(json['required'], isFalse);
      final option = (json['options']! as List).first as Map<String, dynamic>;
      expect(option['role_ids'], ['role-photo']);
      expect(option['channel_ids'], ['ch-general']);
      expect(option['emoji'], '♟');
      // No empty emoji is sent.
      expect(const GuideOptionDraftData(label: ' x ', emoji: ' ').toJson(), {
        'label': 'x',
        'role_ids': <String>[],
        'channel_ids': <String>[],
      });
      // A task that takes no channel sends none.
      expect(
        const GuideTaskDraftData(
          title: 'Avatar',
          action: GuideTaskAction.setAvatar,
          channelId: 'ch-1',
        ).toJson(),
        {'title': 'Avatar', 'action': 'set_avatar'},
      );
    });

    test('a news card reads its attachment', () {
      final notice = NewcomerNotice.maybeFromJson({
        'kind': 'newcomer',
        'user_id': 'user-9',
        'user_label': 'Nia',
        'sticker_id': 'st-1',
      });
      expect(notice?.userLabel, 'Nia');
      expect(notice?.stickerId, 'st-1');
      expect(NewcomerNotice.maybeFromJson({'kind': 'pat'}), isNull);
      expect(NewcomerNotice.maybeFromJson(null), isNull);
    });
  });

  group('the card and the page', () {
    testWidgets('the bar shows progress and the page lists the tasks', (
      tester,
    ) async {
      final rpc = GuideRpc()..answer('get_circle_guide', guideJson());
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();

      expect(find.text('circle body'), findsOneWidget);
      expect(find.byKey(const ValueKey('circle-guide-bar')), findsOneWidget);
      expect(find.text('New member guide'), findsOneWidget);
      // The questions are still waiting too.
      expect(find.text('1 of 3 done · Questions waiting'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('circle-guide-progress')),
      );
      expect(progress.value, closeTo(1 / 3, 0.001));

      await tester.tap(find.byKey(const ValueKey('circle-guide-bar')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('guide-progress-label')),
        findsOneWidget,
      );
      expect(find.text('Read the rules'), findsOneWidget);
      expect(find.text('Have a look around'), findsOneWidget);
      expect(find.text('#general'), findsOneWidget);
      expect(find.text('Add a profile picture'), findsOneWidget);
      // The questions are one row away.
      expect(find.byKey(const ValueKey('guide-open-prompts')), findsOneWidget);
      expect(find.text('Choose what you are into'), findsOneWidget);
    });

    testWidgets('visiting a channel ticks the task and opens the channel', (
      tester,
    ) async {
      final rpc = GuideRpc()
        ..answer('get_circle_guide', guideJson())
        ..answer('complete_guide_task', null);
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('circle-guide-bar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guide-task-task-2')));
      await tester.pumpAndSettle();

      expect(rpc.paramsOf('complete_guide_task').single, {
        'target_circle_id': 'circle-1',
        'target_task_id': 'task-2',
      });
      expect(find.text('opened conv-general'), findsOneWidget);
    });

    testWidgets('no bar when the member put it away, or for older members', (
      tester,
    ) async {
      for (final json in [
        guideJson(dismissed: true),
        guideJson(newMember: false),
      ]) {
        final rpc = GuideRpc()..answer('get_circle_guide', json);
        await tester.pumpWidget(_gate(rpc));
        await tester.pumpAndSettle();
        expect(find.text('circle body'), findsOneWidget);
        expect(find.byKey(const ValueKey('circle-guide-bar')), findsNothing);
      }
    });

    testWidgets('a circle that cannot read its guide looks as it always did', (
      tester,
    ) async {
      // Every call fails, as without a Supabase client.
      await tester.pumpWidget(_gate(GuideRpc()));
      await tester.pumpAndSettle();
      expect(find.text('circle body'), findsOneWidget);
      expect(find.byKey(const ValueKey('circle-guide-bar')), findsNothing);
    });

    testWidgets('the page can bring the card back or put it away', (
      tester,
    ) async {
      final rpc = GuideRpc()
        ..answer('get_circle_guide', guideJson())
        ..answer('dismiss_circle_guide', null);
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('circle-guide-bar')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('guide-show-card')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('guide-show-card')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('dismiss_circle_guide').single, {
        'target_circle_id': 'circle-1',
        'dismissed': true,
      });
    });

    testWidgets('finished tasks say so', (tester) async {
      final rpc = GuideRpc()
        ..answer(
          'get_circle_guide',
          guideJson(
            tasks: [
              guideTaskJson(done: true),
              guideTaskJson(
                id: 'task-2',
                title: 'Say hi',
                action: 'send_message',
                done: true,
              ),
            ],
            prompts: [],
          ),
        );
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();
      // Nothing is left: no bar on the circle.
      expect(find.byKey(const ValueKey('circle-guide-bar')), findsNothing);
    });
  });

  group('the questions', () {
    testWidgets(
      'a new member is asked once, and the answer goes to the server',
      (tester) async {
        final rpc = GuideRpc()
          ..answer('get_circle_guide', guideJson(needsAnswers: true))
          ..answer('complete_onboarding_prompts', {
            'added': [
              {'id': 'role-photo', 'name': 'Photographers'},
            ],
            'removed': <Object>[],
          });
        await tester.pumpWidget(_gate(rpc));
        await tester.pumpAndSettle();

        // The questions open by themselves.
        expect(find.text('About you'), findsOneWidget);
        expect(find.text('What do you play?'), findsOneWidget);
        // What an option gives is said before it is picked.
        expect(find.text('Gives you: Photographers'), findsOneWidget);
        expect(find.text('Shows: #games'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('guide-option-opt-chess')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('guide-prompts-save')));
        await tester.pumpAndSettle();

        expect(rpc.paramsOf('complete_onboarding_prompts').single, {
          'target_circle_id': 'circle-1',
          'option_ids': ['opt-chess'],
        });
        expect(find.text('You now have: Photographers'), findsOneWidget);
        expect(find.text('About you'), findsNothing);
        expect(find.text('circle body'), findsOneWidget);
      },
    );

    testWidgets('a member who is not new is not asked on their own', (
      tester,
    ) async {
      final rpc = GuideRpc()
        ..answer('get_circle_guide', guideJson(newMember: false));
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();
      expect(find.text('About you'), findsNothing);
    });

    testWidgets('a required question must be answered first', (tester) async {
      final rpc = GuideRpc()
        ..answer(
          'get_circle_guide',
          guideJson(
            needsAnswers: true,
            prompts: [guidePromptJson(required: true)],
          ),
        )
        ..answer('complete_onboarding_prompts', {'added': [], 'removed': []});
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();
      expect(find.text('Required · Pick any'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('guide-prompts-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-prompts-error')), findsOneWidget);
      expect(rpc.paramsOf('complete_onboarding_prompts'), isEmpty);
      expect(find.text('About you'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('guide-option-opt-go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-prompts-save')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('complete_onboarding_prompts'), hasLength(1));
    });

    testWidgets('a single-choice question keeps one pick', (tester) async {
      final rpc = GuideRpc()
        ..answer(
          'get_circle_guide',
          guideJson(
            needsAnswers: true,
            prompts: [guidePromptJson(singleSelect: true)],
          ),
        )
        ..answer('complete_onboarding_prompts', {'added': [], 'removed': []});
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();
      expect(find.text('Pick one'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('guide-option-opt-chess')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-option-opt-go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-prompts-save')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('complete_onboarding_prompts').single['option_ids'], [
        'opt-go',
      ]);
    });

    testWidgets('a failed save keeps the page and says so', (tester) async {
      final rpc = GuideRpc()
        ..answer('get_circle_guide', guideJson(needsAnswers: true))
        ..handlers['complete_onboarding_prompts'] = (_) =>
            throw StateError('offline');
      await tester.pumpWidget(_gate(rpc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-option-opt-chess')));
      await tester.tap(find.byKey(const ValueKey('guide-prompts-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save your answers. Try again.'),
        findsOneWidget,
      );
      expect(find.text('About you'), findsOneWidget);
    });

    testWidgets('the rules come first, then the questions', (tester) async {
      final rules = FakeOnboardingDataSource({
        'enabled': true,
        'rules': ['Be kind'],
        'needs_acceptance': true,
      });
      final rpc = GuideRpc()
        ..answer('get_circle_guide', guideJson(needsAnswers: true));
      await tester.pumpWidget(_gate(rpc, rules: rules));
      await tester.pumpAndSettle();

      // Only the rules are out.
      expect(find.text('Rules of Book Club'), findsOneWidget);
      expect(find.text('About you'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('circle-rules-agree')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('circle-rules-accept')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Book Club!'), findsOneWidget);
      expect(find.text('About you'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('circle-welcome-done')));
      await tester.pumpAndSettle();
      expect(find.text('About you'), findsOneWidget);
    });
  });

  group('the card in the channel', () {
    const notice = NewcomerNotice(userId: 'user-9', userLabel: 'Nia');

    testWidgets('Say hello sends the circle sticker', (tester) async {
      final chats = _Chats();
      await tester.pumpWidget(
        _card(
          chats,
          const NewcomerNotice(
            userId: 'user-9',
            userLabel: 'Nia',
            stickerId: 'sticker-wave',
          ),
        ),
      );
      expect(find.text('Nia joined the circle'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('newcomer-say-hello')));
      await tester.pumpAndSettle();
      expect(chats.stickers.single, (
        conversationId: 'conv-welcome',
        stickerId: 'sticker-wave',
      ));
      expect(chats.texts, isEmpty);
      // It is said once.
      expect(find.byKey(const ValueKey('newcomer-say-hello')), findsNothing);
      expect(find.byKey(const ValueKey('newcomer-greeted')), findsOneWidget);
    });

    testWidgets('without a sticker, a waving hand', (tester) async {
      final chats = _Chats();
      await tester.pumpWidget(_card(chats, notice));
      await tester.tap(find.byKey(const ValueKey('newcomer-say-hello')));
      await tester.pumpAndSettle();
      expect(chats.stickers, isEmpty);
      expect(chats.texts.single.body, 'Welcome, Nia! 👋');
    });

    testWidgets('a sticker that is gone falls back to the hand', (
      tester,
    ) async {
      final chats = _Chats()..stickerFails = true;
      await tester.pumpWidget(
        _card(
          chats,
          const NewcomerNotice(
            userId: 'user-9',
            userLabel: 'Nia',
            stickerId: 'gone',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('newcomer-say-hello')));
      await tester.pumpAndSettle();
      expect(chats.texts.single.body, 'Welcome, Nia! 👋');
    });

    testWidgets('a hello that fails says so and can be tried again', (
      tester,
    ) async {
      final chats = _Chats()..textFails = true;
      await tester.pumpWidget(_card(chats, notice));
      await tester.tap(find.byKey(const ValueKey('newcomer-say-hello')));
      await tester.pumpAndSettle();
      expect(find.text('Could not say hello. Try again.'), findsOneWidget);
      expect(find.byKey(const ValueKey('newcomer-say-hello')), findsOneWidget);
    });

    testWidgets('there is no hello to oneself', (tester) async {
      await tester.pumpWidget(_card(_Chats(), notice, me: 'user-9'));
      expect(find.text('Nia joined the circle'), findsOneWidget);
      expect(find.byKey(const ValueKey('newcomer-say-hello')), findsNothing);
    });

    testWidgets('it reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      await tester.pumpWidget(_card(_Chats(), notice));
      expect(find.text('Nia 加入了圈子'), findsOneWidget);
      expect(find.text('打招呼'), findsOneWidget);
    });
  });

  group('the circle', () {
    testWidgets('the guide is in the circle menu, for older members too', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.extraOverrides = [
        circleRpcProvider.overrideWithValue(
          (GuideRpc()..answer('get_circle_guide', guideJson(newMember: false)))
              .call,
        ),
      ];
      await world.open(tester, '/circles/circle-1');
      await settle(tester);
      // Not new, so no card on the circle...
      expect(find.byKey(const ValueKey('circle-guide-bar')), findsNothing);
      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      // ...but the entry is there.
      expect(find.text('Member guide'), findsOneWidget);
    });

    testWidgets('a new member sees the card on the circle', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.extraOverrides = [
        circleRpcProvider.overrideWithValue(
          (GuideRpc()..answer('get_circle_guide', guideJson())).call,
        ),
      ];
      await world.open(tester, '/circles/circle-1');
      await settle(tester);
      expect(find.byKey(const ValueKey('circle-guide-bar')), findsOneWidget);
    });

    testWidgets('a circle without a guide has no entry', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      await settle(tester);
      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      expect(find.text('Member guide'), findsNothing);
    });
  });

  group('the editor', () {
    Widget editor(GuideRpc rpc, {CircleGuideConfig? config}) {
      return ProviderScope(
        retry: noProviderRetry,
        overrides: [
          circleRpcProvider.overrideWithValue(rpc.call),
          circleEmojisProvider('circle-1').overrideWith(
            (ref) async => [
              CircleEmoji(
                id: 'sticker-wave',
                circleId: 'circle-1',
                name: 'wave',
                kind: CircleEmojiKind.sticker,
                storagePath: 'x/wave.png',
                mimeType: 'image/png',
                createdAt: DateTime.utc(2026, 10, 1),
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: GuideEditor(
            detail: circleDetail(),
            initial: config ?? CircleGuideConfig.fromJson(guideConfigJson()),
          ),
        ),
      );
    }

    GuideRpc savingRpc() => GuideRpc()
      ..answer('set_circle_guide_prompts', null)
      ..answer('set_circle_guide_tasks', null)
      ..answer('set_circle_greeting', null);

    Future<void> tall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('it shows what the circle has and saves it unchanged', (
      tester,
    ) async {
      await tall(tester);
      final rpc = savingRpc();
      await tester.pumpWidget(editor(rpc));
      await tester.pumpAndSettle();
      expect(find.text('What do you play?'), findsOneWidget);
      expect(find.text('Chess'), findsOneWidget);
      expect(find.text('Read the rules'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
      await tester.pumpAndSettle();

      final prompts =
          rpc.paramsOf('set_circle_guide_prompts').single['prompt_list']!
              as List;
      expect((prompts.single as Map)['id'], 'prompt-1');
      expect(
        (((prompts.single as Map)['options']! as List).first
            as Map)['role_ids'],
        ['role-photo'],
      );
      expect(rpc.paramsOf('set_circle_guide_tasks').single['task_list'], [
        {'id': 'task-1', 'title': 'Read the rules', 'action': 'read_rules'},
      ]);
      expect(rpc.paramsOf('set_circle_greeting').single, {
        'target_circle_id': 'circle-1',
        'target_channel_id': null,
        'target_sticker_id': null,
      });
    });

    testWidgets('roles with management power are shown but cannot be picked', (
      tester,
    ) async {
      await tall(tester);
      final rpc = savingRpc();
      await tester.pumpWidget(editor(rpc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-option-more-0-1')));
      await tester.pumpAndSettle();

      // Moderators have manage_messages: marked, and a tap does nothing.
      final moderators = find.byKey(
        const ValueKey('guide-option-role-0-1-role-mods'),
      );
      expect(moderators, findsOneWidget);
      expect(find.text('Moderators of the Valley'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
      expect(
        find.text(
          'Roles with a lock have management permissions and cannot be given.',
        ),
        findsOneWidget,
      );
      await tester.tap(moderators);
      await tester.pumpAndSettle();
      // Photographers has no permission at all.
      await tester.tap(
        find.byKey(const ValueKey('guide-option-role-0-1-role-photo')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
      await tester.pumpAndSettle();
      final prompts =
          rpc.paramsOf('set_circle_guide_prompts').single['prompt_list']!
              as List;
      final go = ((prompts.single as Map)['options']! as List)[1] as Map;
      expect(go['role_ids'], [
        'role-photo',
      ], reason: 'Go now gives Photographers');
    });

    testWidgets('a new question and a new task are saved', (tester) async {
      await tall(tester);
      final rpc = savingRpc();
      await tester.pumpWidget(editor(rpc));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guide-add-prompt')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('guide-prompt-title-1')),
        'Which timezone?',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guide-option-label-1-0')),
        'Europe',
      );
      await tester.tap(find.byKey(const ValueKey('guide-prompt-required-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guide-add-task')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('guide-task-kind-1-visit_channel')),
      );
      await tester.pumpAndSettle();
      // Visiting needs a channel.
      await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-editor-error')), findsOneWidget);
      expect(rpc.paramsOf('set_circle_guide_prompts'), isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('guide-task-channel-1-ch-general')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
      await tester.pumpAndSettle();

      final prompts =
          rpc.paramsOf('set_circle_guide_prompts').single['prompt_list']!
              as List;
      expect(prompts, hasLength(2));
      final added = prompts.last as Map;
      expect(
        added.containsKey('id'),
        isFalse,
        reason: 'a new question has no id',
      );
      expect(added['title'], 'Which timezone?');
      expect(added['required'], isTrue);
      expect(((added['options']! as List).single as Map)['label'], 'Europe');
      final tasks =
          rpc.paramsOf('set_circle_guide_tasks').single['task_list']! as List;
      expect(tasks.last, {
        'title': 'Have a look around',
        'action': 'visit_channel',
        'channel_id': 'ch-general',
      });
    });

    testWidgets('an empty question is not saved', (tester) async {
      await tall(tester);
      final rpc = savingRpc();
      await tester.pumpWidget(editor(rpc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-add-prompt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
      await tester.pumpAndSettle();
      expect(find.text('Every question needs its words.'), findsOneWidget);
      expect(rpc.calls, isEmpty);
    });

    testWidgets('the greeting picks a channel and a sticker', (tester) async {
      await tall(tester);
      final rpc = savingRpc();
      await tester.pumpWidget(editor(rpc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-greeting-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('guide-greeting-sticker-sticker-wave')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
      await tester.pumpAndSettle();
      final greeting = rpc.paramsOf('set_circle_greeting').single;
      expect(greeting['target_channel_id'], isNotNull);
      expect(greeting['target_sticker_id'], 'sticker-wave');
    });

    testWidgets('the server refusing a role is explained', (tester) async {
      await tall(tester);
      final rpc = savingRpc()
        ..handlers['set_circle_guide_prompts'] = (_) {
          throw const PostgrestExceptionStub();
        };
      await tester.pumpWidget(editor(rpc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-editor-error')), findsOneWidget);
    });
  });
}

/// Stands for any error the save can fail with.
class PostgrestExceptionStub implements Exception {
  const PostgrestExceptionStub();
}
