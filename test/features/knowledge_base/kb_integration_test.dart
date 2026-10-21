import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/features/circles/guard2/guard_items_section.dart';
import 'package:wecord/features/circles/onboarding/guide_editor_screen.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/features/circles/onboarding/guide_page.dart';
import 'package:wecord/features/knowledge_base/kb_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';
import '../circles/circle_onboarding_test.dart' show FakeOnboardingDataSource;
import '../circles/guard2_fakes.dart' show itemJson;
import '../circles/onboarding_guide_fakes.dart';
import 'kb_fakes.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('in the app', () {
    testWidgets('the circle menu has a knowledge base entry that opens it', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = KbWorld()..install();
      await world.world.open(tester, '/circles/circle-1');
      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      final entry = find.text('Knowledge base');
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await settle(tester);
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Resources'), findsOneWidget);
      expect(world.knowledge.calls, contains('list:circle-1'));
    });

    testWidgets('a link to a page opens it', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = KbWorld()..install();
      await world.world.open(
        tester,
        '/circles/circle-1/knowledge?page=p-welcome',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Start here'), findsOneWidget);
      expect(world.knowledge.calls, contains('read:p-welcome'));
    });

    testWidgets('a link to the knowledge base opens the tree', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = KbWorld()..install();
      await world.world.open(tester, '/circles/circle-1/knowledge');
      expect(find.text('Knowledge base'), findsOneWidget);
      expect(find.text('Rules'), findsOneWidget);
    });
  });

  group('required reading in the guide', () {
    test('a task that reads a page carries the page', () {
      final task = GuideTask.fromJson(
        guideTaskJson(action: 'read_page')
          ..['page_id'] = 'p-rules'
          ..['page_title'] = 'Rules',
      );
      expect(task.action, GuideTaskAction.readPage);
      expect(task.pageId, 'p-rules');
      expect(task.pageTitle, 'Rules');
      expect(GuideTaskAction.readPage.needsPage, isTrue);
      expect(GuideTaskAction.readPage.takesChannel, isFalse);
      final draft = GuideTaskDraftData(
        title: 'Read it',
        action: GuideTaskAction.readPage,
        channelId: 'ignored',
        pageId: 'p-rules',
      );
      expect(draft.toJson(), {
        'title': 'Read it',
        'action': 'read_page',
        'page_id': 'p-rules',
      });
      expect(
        const GuideTaskDraftData(
          title: 'Hi',
          action: GuideTaskAction.setAvatar,
          pageId: 'x',
        ).toJson().containsKey('page_id'),
        isFalse,
      );
    });

    Widget guidePage(GuideRpc rpc, KbWorld world) {
      world.install();
      return ProviderScope(
        retry: noProviderRetry,
        overrides: [
          ...world.world.overrides,
          circleRpcProvider.overrideWithValue(rpc.call),
          circleOnboardingRepositoryProvider.overrideWithValue(
            CircleOnboardingRepository(
              FakeOnboardingDataSource({
                'enabled': false,
                'rules': <String>[],
                'needs_acceptance': false,
              }),
            ),
          ),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: const CircleGuidePage(
            circleId: 'circle-1',
            circleName: 'Book Club',
          ),
        ),
      );
    }

    testWidgets('the task shows the page and opens it', (tester) async {
      final world = KbWorld();
      final rpc = GuideRpc()
        ..answer(
          'get_circle_guide',
          guideJson(
            prompts: const [],
            tasks: [
              guideTaskJson(
                  id: 'task-read',
                  title: 'Read the welcome page',
                  action: 'read_page',
                )
                ..['page_id'] = 'p-welcome'
                ..['page_title'] = 'Welcome',
            ],
          ),
        );
      await tester.pumpWidget(guidePage(rpc, world));
      await tester.pumpAndSettle();
      expect(find.text('Read the welcome page'), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-task-task-read')));
      await tester.pumpAndSettle();
      expect(find.text('Start here'), findsOneWidget);
      expect(world.knowledge.calls, contains('read:p-welcome'));
    });

    group('the editor', () {
      Widget editor(GuideRpc rpc, KbWorld world) {
        return ProviderScope(
          retry: noProviderRetry,
          overrides: [
            circleRpcProvider.overrideWithValue(rpc.call),
            ...world.overrides,
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: GuideEditor(
              detail: circleDetail(),
              initial: CircleGuideConfig.fromJson(
                guideConfigJson(prompts: const []),
              ),
            ),
          ),
        );
      }

      GuideRpc savingRpc() => GuideRpc()
        ..answer('set_circle_guide_prompts', null)
        ..answer('set_circle_guide_tasks', null)
        ..answer('set_circle_greeting', null);

      void tall(WidgetTester tester) {
        tester.view.physicalSize = const Size(900, 4200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }

      testWidgets('a reading task needs a page, then saves it', (tester) async {
        tall(tester);
        final world = KbWorld();
        final rpc = savingRpc();
        await tester.pumpWidget(editor(rpc, world));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('guide-add-task')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('guide-task-kind-1-read_page')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Page to read'), findsOneWidget);
        expect(
          find.widgetWithText(Text, 'Read the welcome page'),
          findsNothing,
          reason: 'the title field holds it, not a label',
        );

        // Nothing picked: it will not save.
        await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
        await tester.pumpAndSettle();
        expect(find.text('Pick the page to read.'), findsOneWidget);
        expect(rpc.paramsOf('set_circle_guide_tasks'), isEmpty);

        await tester.tap(find.byKey(const ValueKey('guide-task-page-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('kb-move-p-rules')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('kb-move-p-rules')));
        await tester.pumpAndSettle();
        // The button now names the page.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('guide-task-page-1')),
            matching: find.text('Rules'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
        await tester.pumpAndSettle();
        final tasks =
            rpc.paramsOf('set_circle_guide_tasks').single['task_list']! as List;
        expect(tasks.last, {
          'title': 'Read the welcome page',
          'action': 'read_page',
          'page_id': 'p-rules',
        });
      });

      testWidgets('with no pages it says to add one first', (tester) async {
        tall(tester);
        final world = KbWorld();
        world.knowledge.pages = [];
        await tester.pumpWidget(editor(savingRpc(), world));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('guide-add-task')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('guide-task-kind-1-read_page')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'This circle has no knowledge base pages yet. Add one first.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('guide-task-page-1')), findsNothing);
      });

      testWidgets('a task the server sends keeps its page', (tester) async {
        tall(tester);
        final world = KbWorld();
        final rpc = savingRpc();
        await tester.pumpWidget(
          ProviderScope(
            retry: noProviderRetry,
            overrides: [
              circleRpcProvider.overrideWithValue(rpc.call),
              ...world.overrides,
            ],
            child: MaterialApp(
              theme: WeCordTheme.light(),
              home: GuideEditor(
                detail: circleDetail(),
                initial: CircleGuideConfig.fromJson(
                  guideConfigJson(
                    prompts: const [],
                    tasks: [
                      {
                        'id': 'task-9',
                        'title': 'Rules first',
                        'action': 'read_page',
                        'channel_id': null,
                        'page_id': 'p-rules',
                        'page_title': 'Rules',
                      },
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('guide-editor-save')));
        await tester.pumpAndSettle();
        expect(rpc.paramsOf('set_circle_guide_tasks').single['task_list'], [
          {
            'id': 'task-9',
            'title': 'Rules first',
            'action': 'read_page',
            'page_id': 'p-rules',
          },
        ]);
      });
    });
  });

  group('the AI guard review queue', () {
    testWidgets('a flagged page opens in the knowledge base', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final opened = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: SingleChildScrollView(
                child: GuardItemCard(
                  item: GuardItemReview.fromJson({
                    ...itemJson(),
                    'conversation_id': null,
                    'channel_id': null,
                    'channel_name': null,
                    'item_id': 'p-rules',
                  }),
                  circleId: 'circle-1',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/circles/:circleId/knowledge',
            builder: (context, state) {
              opened.add(
                '${state.pathParameters['circleId']}:'
                '${state.uri.queryParameters['page']}',
              );
              return const Scaffold(body: Text('knowledge base opened'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          child: MaterialApp.router(
            theme: WeCordTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-item-open')));
      await tester.pumpAndSettle();
      expect(opened, ['circle-1:p-rules']);
      expect(find.text('knowledge base opened'), findsOneWidget);
    });
  });

  test('the repository is the uninitialized one without Supabase', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(knowledgeBaseRepositoryProvider),
      isA<UninitializedKnowledgeBaseRepository>(),
    );
  });
}
