import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/mod_tools/ban_appeals_section.dart';
import 'package:wecord/features/circles/mod_tools/ban_inbox_card.dart';
import 'package:wecord/features/circles/mod_tools/member_tools_screen.dart';
import 'package:wecord/features/circles/mod_tools/mod_notes_screen.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/features/circles/mod_tools/raid_alert_card.dart';
import 'package:wecord/features/circles/mod_tools/raid_protection.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'mod_tools_fakes.dart';

final _now = DateTime.utc(2026, 10, 25, 12);

Widget _app(
  Widget home,
  JoinRpc rpc, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    retry: noProviderRetry,
    overrides: [...modToolsOverrides(rpc), ...overrides],
    child: MaterialApp(theme: WeCordTheme.light(), home: home),
  );
}

void _tall(WidgetTester tester, {Size size = const Size(800, 2400)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('models and repository', () {
    test('a member row parses, with what the caller may do', () {
      final member = ModMember.fromJson(
        modMemberJson(warnings: 2, flagged: true, canBan: false),
      );
      expect(member.name, 'Nia Novak');
      expect(member.warningCount, 2);
      expect(member.flagged, isTrue);
      expect(member.canTimeout && member.canKick, isTrue);
      expect(member.canBan, isFalse);
      expect(member.actionable, isTrue);
      expect(
        ModMember.fromJson(
          modMemberJson(canTimeout: false, canKick: false, canBan: false),
        ).actionable,
        isFalse,
      );
    });

    test('the filter counts what is on and sends its parameters', () {
      const empty = ModMemberFilter();
      expect(empty.activeCount, 0);
      final filter = empty.copyWith(
        joinedWithinDays: 7,
        maxMessages: 0,
        onlyFlagged: true,
        query: ' ada ',
      );
      expect(filter.activeCount, 3);
      expect(filter.toParams(), {
        'joined_within_days': 7,
        'joined_before_days': null,
        'account_within_days': null,
        'min_messages': null,
        'max_messages': 0,
        'filter_role_id': null,
        'only_flagged': true,
        'name_query': 'ada',
      });
      expect(filter.copyWith(maxMessages: null).maxMessages, isNull);
      expect(filter == filter.copyWith(), isTrue);
      expect(filter == filter.copyWith(onlyFlagged: false), isFalse);
    });

    test('a batch answer says who was refused', () {
      final outcome = BatchOutcome.fromJson({
        'done': 1,
        'results': [
          {'user_id': 'a', 'ok': true},
          {'user_id': 'b', 'ok': false, 'error': 'rank', 'code': '42501'},
        ],
        'media': [],
      });
      expect(outcome.requested, 2);
      expect(outcome.done, 1);
      expect(outcome.failures, ['b']);
      expect(outcome.allDone, isFalse);
    });

    test('security and lock states parse', () {
      final security = CircleSecurity.fromJson(
        securityJson(
          lockdown: lockdownJson(),
          invitesPausedUntil: '2099-01-01T10:00:00Z',
          recentJoins: 5,
        ),
      );
      expect(security.lockedDown && security.invitesPaused, isTrue);
      expect(security.lockdown!.automatic, isTrue);
      expect(security.lockdown!.joins, 24);
      expect(security.active, isTrue);
      expect(CircleSecurity.fromJson(securityJson()).active, isFalse);
      final lock = ThreadLockState.fromJson({
        'thread_id': 't1',
        'locked': true,
        'can_lock': false,
        'can_post': false,
      });
      expect(lock.locked && !lock.canPost && !lock.canLock, isTrue);
      expect(
        MyCircleBan.fromJson(myBanJson(appealStatus: 'denied')).canAppeal,
        isFalse,
      );
      expect(MyCircleBan.fromJson(myBanJson()).canAppeal, isTrue);
    });

    test('a ban says when it ends', () {
      expect(banEndLabel(null), 'Permanent');
      expect(
        banEndLabel(
          DateTime(2026, 10, 25, 15, 30),
          now: DateTime(2026, 10, 25),
        ),
        'Ends 15:30',
      );
      expect(
        banEndLabel(DateTime(2026, 10, 28, 9, 5), now: DateTime(2026, 10, 25)),
        'Ends 10/28 09:05',
      );
    });

    test('the repository sends the right parameters', () async {
      final rpc = JoinRpc()
        ..answer('list_circle_members_for_moderation', [modMemberJson()])
        ..answer('batch_moderate_circle_members', {
          'done': 1,
          'results': [
            {'user_id': 'u1', 'ok': true},
          ],
          'media': [],
        })
        ..answer('add_circle_mod_note', 'n1')
        ..answer('delete_circle_mod_note', null)
        ..answer('decide_ban_appeal', null)
        ..answer('submit_ban_appeal', 'a1')
        ..answer('set_circle_raid_settings', null)
        ..answer('pause_circle_invites', null)
        ..answer('start_circle_lockdown', null)
        ..answer('set_thread_locked', null)
        ..answer('get_thread_lock_state', null);
      final repository = ModToolsRepository(rpc.call);

      final page = await repository.listMembers(
        'c1',
        const ModMemberFilter(joinedWithinDays: 7),
        limit: 20,
        offset: 40,
      );
      expect(page.members.single.userId, 'u1');
      expect(page.total, 1);
      expect(rpc.paramsOf('list_circle_members_for_moderation').single, {
        'target_circle_id': 'c1',
        'joined_within_days': 7,
        'joined_before_days': null,
        'account_within_days': null,
        'min_messages': null,
        'max_messages': null,
        'filter_role_id': null,
        'only_flagged': false,
        'name_query': null,
        'result_limit': 20,
        'result_offset': 40,
      });

      await repository.batch(
        'c1',
        ['u1'],
        BatchAction.ban,
        seconds: 3600,
        reason: ' raid ',
      );
      expect(rpc.paramsOf('batch_moderate_circle_members').single, {
        'target_circle_id': 'c1',
        'target_user_ids': ['u1'],
        'batch_action': 'ban',
        'duration_seconds': 3600,
        'batch_reason': 'raid',
      });

      await repository.addNote('c1', 'u1', ModNoteKind.warning, ' links ');
      expect(rpc.paramsOf('add_circle_mod_note').single, {
        'target_circle_id': 'c1',
        'target_user_id': 'u1',
        'note_kind': 'warning',
        'note_body': 'links',
      });
      await repository.deleteNote('n1');
      expect(rpc.paramsOf('delete_circle_mod_note').single, {
        'target_note_id': 'n1',
      });
      await repository.decideAppeal('a1', approve: false, note: ' not yet ');
      expect(rpc.paramsOf('decide_ban_appeal').single, {
        'target_appeal_id': 'a1',
        'approve': false,
        'decision_note': 'not yet',
      });
      await repository.submitAppeal('c1', ' sorry ');
      expect(rpc.paramsOf('submit_ban_appeal').single, {
        'target_circle_id': 'c1',
        'appeal_message': 'sorry',
      });
      await repository.saveRaidSettings(
        'c1',
        enabled: true,
        threshold: 50,
        lockHours: 24,
      );
      expect(rpc.paramsOf('set_circle_raid_settings').single, {
        'target_circle_id': 'c1',
        'protection_enabled': true,
        'join_threshold': 50,
        'lockdown_hours': 24,
      });
      await repository.pauseInvites('c1', 1);
      await repository.startLockdown('c1', 24);
      expect(rpc.paramsOf('pause_circle_invites').single, {
        'target_circle_id': 'c1',
        'pause_hours': 1,
      });
      expect(rpc.paramsOf('start_circle_lockdown').single, {
        'target_circle_id': 'c1',
        'lockdown_hours': 24,
      });
      await repository.setThreadLocked('t1', locked: true);
      expect(rpc.paramsOf('set_thread_locked').single, {
        'target_thread_id': 't1',
        'locked': true,
      });
      expect(await repository.threadLockState('conv-1'), isNull);
    });
  });

  group('the member list', () {
    Future<JoinRpc> pumpMembers(
      WidgetTester tester, {
      List<Map<String, dynamic>>? rows,
    }) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer(
          'list_circle_members_for_moderation',
          rows ??
              [
                modMemberJson(
                  id: 'u1',
                  name: 'Nia Novak',
                  username: 'nia',
                  flagged: true,
                  warnings: 2,
                  total: 3,
                ),
                modMemberJson(
                  id: 'u2',
                  name: 'Omar Haddad',
                  username: 'omar',
                  accountCreatedAt: '2026-10-24T09:00:00Z',
                  total: 3,
                ),
                modMemberJson(
                  id: 'u3',
                  name: 'Sam Senior',
                  username: 'sam',
                  canTimeout: false,
                  canKick: false,
                  canBan: false,
                  total: 3,
                ),
              ],
        )
        ..answer('batch_moderate_circle_members', {
          'done': 2,
          'results': [
            {'user_id': 'u1', 'ok': true},
            {'user_id': 'u2', 'ok': true},
          ],
          'media': [],
        })
        ..answer('list_circle_mod_notes', [modNoteJson()]);
      await tester.pumpWidget(
        _app(MemberToolsScreen(circleId: 'circle-1', now: () => _now), rpc),
      );
      await tester.pumpAndSettle();
      return rpc;
    }

    testWidgets('rows show what a moderator weighs', (tester) async {
      await pumpMembers(tester);
      expect(find.text('Nia Novak'), findsOneWidget);
      expect(find.text('Omar Haddad'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      expect(find.text('Flagged'), findsOneWidget);
      expect(find.text('2 warnings'), findsOneWidget);
      // Omar's account is a day old.
      expect(find.text('New account'), findsWidgets);
      expect(find.textContaining('3 messages'), findsWidgets);
    });

    testWidgets('a tap opens the notes about the member', (tester) async {
      await pumpMembers(tester);
      await tester.tap(find.byKey(const ValueKey('member-tools-u1')));
      await tester.pumpAndSettle();
      expect(find.byType(ModNotesScreen), findsOneWidget);
      expect(find.text('Asked to stop posting links'), findsOneWidget);
    });

    testWidgets('filters go to the server, and the summary shows them', (
      tester,
    ) async {
      final rpc = await pumpMembers(tester);
      await tester.tap(find.byKey(const ValueKey('member-tools-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-joined-7')));
      await tester.tap(find.byKey(const ValueKey('filter-messages-none')));
      await tester.tap(find.byKey(const ValueKey('filter-flagged')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-apply')));
      await tester.pumpAndSettle();
      final last = rpc.paramsOf('list_circle_members_for_moderation').last;
      expect(last['joined_within_days'], 7);
      expect(last['max_messages'], 0);
      expect(last['only_flagged'], isTrue);
      expect(
        find.text('Joined in the last 7 days · No messages · Flagged'),
        findsOneWidget,
      );
      // Reset clears them again.
      await tester.tap(find.byKey(const ValueKey('member-tools-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-reset')));
      await tester.pumpAndSettle();
      expect(
        rpc.paramsOf('list_circle_members_for_moderation').last['only_flagged'],
        isFalse,
      );
      expect(find.byKey(const ValueKey('member-tools-summary')), findsNothing);
    });

    testWidgets('searching waits a moment, then asks', (tester) async {
      final rpc = await pumpMembers(tester);
      await tester.enterText(
        find.byKey(const ValueKey('member-tools-search')),
        'omar',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(rpc.paramsOf('list_circle_members_for_moderation'), hasLength(1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        rpc.paramsOf('list_circle_members_for_moderation').last['name_query'],
        'omar',
      );
    });

    testWidgets('more pages are loaded on request', (tester) async {
      final rpc = await pumpMembers(
        tester,
        rows: [modMemberJson(id: 'u1', total: 51)],
      );
      rpc.handlers['list_circle_members_for_moderation'] = (params) => [
        modMemberJson(
          id: params['result_offset'] == 0 ? 'u1' : 'u9',
          total: 51,
        ),
      ];
      await tester.tap(find.byKey(const ValueKey('member-tools-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-apply')));
      await tester.pumpAndSettle();
      expect(find.text('51 members'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('member-tools-more')),
      );
      await tester.tap(find.byKey(const ValueKey('member-tools-more')));
      await tester.pumpAndSettle();
      expect(
        rpc
            .paramsOf('list_circle_members_for_moderation')
            .last['result_offset'],
        1,
      );
    });

    testWidgets('choosing members, the bar follows what the caller may do', (
      tester,
    ) async {
      await pumpMembers(tester);
      expect(find.byKey(const ValueKey('member-tools-bar')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('member-tools-select')));
      await tester.pumpAndSettle();
      expect(find.text('Choose members'), findsOneWidget);

      // Sam cannot be chosen: tapping does nothing.
      await tester.tap(find.byKey(const ValueKey('member-tools-u3')));
      await tester.pumpAndSettle();
      expect(find.text('Choose members'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('member-tools-u1')));
      await tester.tap(find.byKey(const ValueKey('member-tools-u2')));
      await tester.pumpAndSettle();
      expect(find.text('2 chosen'), findsOneWidget);
      WeCordButton button(String key) =>
          tester.widget<WeCordButton>(find.byKey(ValueKey(key)));
      expect(button('member-tools-timeout').onPressed, isNotNull);
      expect(button('member-tools-kick').onPressed, isNotNull);
      expect(button('member-tools-ban').onPressed, isNotNull);

      // Select all picks the ones that can be acted on, then none.
      await tester.tap(find.byKey(const ValueKey('member-tools-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('Choose members'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('member-tools-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('2 chosen'), findsOneWidget);
    });

    testWidgets('time out, remove and ban several at once', (tester) async {
      final rpc = await pumpMembers(tester);
      await tester.tap(find.byKey(const ValueKey('member-tools-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('member-tools-u1')));
      await tester.tap(find.byKey(const ValueKey('member-tools-u2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('member-tools-timeout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-timeout-3600')));
      await tester.pumpAndSettle();
      var call = rpc.paramsOf('batch_moderate_circle_members').last;
      expect(call['batch_action'], 'timeout');
      expect(call['duration_seconds'], 3600);
      expect(call['target_user_ids'], ['u1', 'u2']);
      expect(find.text('Timed out 2 members.'), findsOneWidget);

      // The list reloads and the selection is gone.
      expect(find.byKey(const ValueKey('member-tools-bar')), findsNothing);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();

      await tester.tap(find.byKey(const ValueKey('member-tools-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('member-tools-u1')));
      await tester.tap(find.byKey(const ValueKey('member-tools-u2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('member-tools-kick')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CircleDialog),
          matching: find.text('Remove'),
        ),
      );
      await tester.pumpAndSettle();
      call = rpc.paramsOf('batch_moderate_circle_members').last;
      expect(call['batch_action'], 'kick');

      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.tap(find.byKey(const ValueKey('member-tools-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('member-tools-u1')));
      await tester.tap(find.byKey(const ValueKey('member-tools-u2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('member-tools-ban')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ban-duration-86400')));
      await tester.enterText(
        find.byKey(const ValueKey('batch-ban-reason')),
        'raid',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('batch-ban-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-ban-confirm')));
      await tester.pumpAndSettle();
      call = rpc.paramsOf('batch_moderate_circle_members').last;
      expect(call['batch_action'], 'ban');
      expect(call['duration_seconds'], 86400);
      expect(call['batch_reason'], 'raid');
    });

    testWidgets('a partly refused batch says so', (tester) async {
      final rpc = await pumpMembers(tester);
      rpc.answer('batch_moderate_circle_members', {
        'done': 1,
        'results': [
          {'user_id': 'u1', 'ok': true},
          {'user_id': 'u2', 'ok': false, 'error': 'rank', 'code': '42501'},
        ],
        'media': [],
      });
      await tester.tap(find.byKey(const ValueKey('member-tools-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('member-tools-u1')));
      await tester.tap(find.byKey(const ValueKey('member-tools-u2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('member-tools-timeout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-timeout-60')));
      await tester.pumpAndSettle();
      expect(
        find.text('Done for 1 of 2. The others could not be changed.'),
        findsOneWidget,
      );
    });

    testWidgets('no match says so', (tester) async {
      await pumpMembers(tester, rows: const []);
      expect(find.byKey(const ValueKey('member-tools-empty')), findsOneWidget);
    });
  });

  group('notes and warnings', () {
    testWidgets('lists, adds a warning, and deletes', (tester) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer('list_circle_mod_notes', [
          modNoteJson(),
          modNoteJson(id: 'n2', kind: 'warning', body: 'Second link today'),
          modNoteJson(id: 'n3', body: 'Not mine', canDelete: false),
        ])
        ..answer('add_circle_mod_note', 'n9')
        ..answer('delete_circle_mod_note', null);
      await tester.pumpWidget(
        _app(
          ModNotesScreen(
            circleId: 'circle-1',
            userId: 'u1',
            name: 'Nia',
            now: () => _now,
          ),
          rpc,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notes · 1 warning'), findsOneWidget);
      expect(find.text('Second link today'), findsOneWidget);
      expect(find.byKey(const ValueKey('mod-note-delete-n3')), findsNothing);
      expect(
        find.text('Only moderators see notes and warnings. Nia is not told.'),
        findsOneWidget,
      );

      // Empty text cannot be added.
      expect(
        tester
            .widget<WeCordButton>(find.byKey(const ValueKey('mod-note-add')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('mod-note-kind-warning')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mod-note-body')),
        'Posted a link again',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mod-note-add')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('add_circle_mod_note').single, {
        'target_circle_id': 'circle-1',
        'target_user_id': 'u1',
        'note_kind': 'warning',
        'note_body': 'Posted a link again',
      });
      expect(find.text('Warning added.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mod-note-delete-n1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('delete_circle_mod_note').single, {
        'target_note_id': 'n1',
      });
    });

    testWidgets('no notes yet', (tester) async {
      _tall(tester);
      final rpc = JoinRpc()..answer('list_circle_mod_notes', const []);
      await tester.pumpWidget(
        _app(
          const ModNotesScreen(circleId: 'circle-1', userId: 'u1', name: 'Nia'),
          rpc,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mod-notes-empty')), findsOneWidget);
    });
  });

  group('the Review page extras', () {
    Future<JoinRpc> pumpReview(
      WidgetTester tester, {
      Map<String, dynamic>? security,
      List<Map<String, dynamic>> appeals = const [],
    }) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer('get_circle_security', security ?? securityJson())
        ..answer('list_ban_appeals', appeals)
        ..answer('count_ban_appeals', appeals.length)
        ..answer('decide_ban_appeal', null)
        ..answer('end_circle_lockdown', true)
        ..answer('resume_circle_invites', null);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ModToolsReviewHost(
              circleId: 'circle-1',
              now: () => _now,
              child: const Center(child: Text('the rest of the page')),
            ),
          ),
          rpc,
        ),
      );
      await tester.pumpAndSettle();
      return rpc;
    }

    testWidgets('all quiet: nothing extra', (tester) async {
      await pumpReview(tester);
      expect(find.byKey(const ValueKey('raid-banner')), findsNothing);
      expect(find.byKey(const ValueKey('mod-tools-panel')), findsNothing);
      expect(find.text('the rest of the page'), findsOneWidget);
    });

    testWidgets('a lockdown shows a banner with one button to end it', (
      tester,
    ) async {
      final rpc = await pumpReview(
        tester,
        security: securityJson(
          lockdown: lockdownJson(),
          invitesPausedUntil: '2099-01-01T10:00:00Z',
        ),
      );
      expect(find.text('Raid protection locked this circle'), findsOneWidget);
      expect(
        find.textContaining(
          '24 people joined or asked to join within 10 minutes.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('raid-end-lockdown')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('end_circle_lockdown').single, {
        'target_circle_id': 'circle-1',
      });
      expect(find.text('Lockdown ended.'), findsOneWidget);
    });

    testWidgets('paused invites can be resumed', (tester) async {
      final rpc = await pumpReview(
        tester,
        security: securityJson(invitesPausedUntil: '2099-01-01T10:00:00Z'),
      );
      expect(find.text('Invites are paused'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('raid-resume-invites')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('resume_circle_invites'), hasLength(1));
    });

    testWidgets('appeals: lift a ban, or turn the appeal down with a note', (
      tester,
    ) async {
      final rpc = await pumpReview(
        tester,
        appeals: [
          banAppealJson(),
          banAppealJson(id: 'a2', name: 'Fay', username: 'fay'),
        ],
      );
      expect(find.text('Ban appeals'), findsOneWidget);
      expect(find.byKey(const ValueKey('ban-appeals-count')), findsOneWidget);
      expect(
        find.text('I am sorry, it will not happen again.'),
        findsNWidgets(2),
      );
      expect(find.textContaining('Banned by Sam'), findsWidgets);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('ban-appeal-a1')),
          matching: find.byKey(const ValueKey('ban-appeal-approve')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CircleDialog),
          matching: find.text('Lift ban'),
        ),
      );
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('decide_ban_appeal').single, {
        'target_appeal_id': 'a1',
        'approve': true,
      });

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('ban-appeal-a2')),
          matching: find.byKey(const ValueKey('ban-appeal-deny')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ban-appeal-note')),
        'not yet',
      );
      await tester.tap(find.byKey(const ValueKey('ban-appeal-deny-confirm')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('decide_ban_appeal').last, {
        'target_appeal_id': 'a2',
        'approve': false,
        'decision_note': 'not yet',
      });
    });
  });

  group('raid protection', () {
    Future<JoinRpc> pumpScreen(
      WidgetTester tester, {
      Map<String, dynamic>? security,
    }) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer(
          'get_circle_security',
          security ?? securityJson(recentJoins: 4, recentNew: 1),
        )
        ..answer('pause_circle_invites', null)
        ..answer('resume_circle_invites', null)
        ..answer('start_circle_lockdown', null)
        ..answer('end_circle_lockdown', true)
        ..answer('set_circle_raid_settings', null);
      await tester.pumpWidget(
        _app(RaidProtectionScreen(circleId: 'circle-1', now: () => _now), rpc),
      );
      await tester.pumpAndSettle();
      return rpc;
    }

    testWidgets('quick actions pause invites and lock down', (tester) async {
      final rpc = await pumpScreen(tester);
      expect(find.byKey(const ValueKey('raid-recent')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('raid-pause-24')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('pause_circle_invites').single['pause_hours'], 24);
      await tester.tap(find.byKey(const ValueKey('raid-lock-1')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('start_circle_lockdown').single['lockdown_hours'], 1);
    });

    testWidgets('a lockdown offers to end it, not to start another', (
      tester,
    ) async {
      final rpc = await pumpScreen(
        tester,
        security: securityJson(
          lockdown: lockdownJson(source: 'manual'),
          invitesPausedUntil: '2099-01-01T10:00:00Z',
        ),
      );
      expect(find.byKey(const ValueKey('raid-lock-1')), findsNothing);
      expect(find.byKey(const ValueKey('raid-pause-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('raid-end')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('end_circle_lockdown'), hasLength(1));
    });

    testWidgets('managers change when it locks itself', (tester) async {
      final rpc = await pumpScreen(tester);
      WeCordButton save() =>
          tester.widget<WeCordButton>(find.byKey(const ValueKey('raid-save')));
      expect(save().onPressed, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('raid-threshold-50')),
      );
      await tester.tap(find.byKey(const ValueKey('raid-threshold-50')));
      await tester.tap(find.byKey(const ValueKey('raid-hours-24')));
      await tester.pumpAndSettle();
      expect(save().onPressed, isNotNull);
      await tester.ensureVisible(find.byKey(const ValueKey('raid-save')));
      await tester.tap(find.byKey(const ValueKey('raid-save')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('set_circle_raid_settings').single, {
        'target_circle_id': 'circle-1',
        'protection_enabled': true,
        'join_threshold': 50,
        'lockdown_hours': 24,
      });
    });

    testWidgets('moderators who do not manage the circle only read them', (
      tester,
    ) async {
      await pumpScreen(tester, security: securityJson(canManage: false));
      expect(find.byKey(const ValueKey('raid-save')), findsNothing);
      expect(
        find.text('Only members who can manage the circle can change these.'),
        findsOneWidget,
      );
    });

    testWidgets('the circle menu dialog does the same in one tap', (
      tester,
    ) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer('get_circle_security', securityJson())
        ..answer('pause_circle_invites', null);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showCircleSafetyActions(context, 'circle-1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          rpc,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Safety actions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('safety-pause-1')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('pause_circle_invites').single['pause_hours'], 1);
      expect(find.text('Safety actions'), findsNothing);
    });
  });

  group('being banned', () {
    testWidgets('the card offers one appeal, and shows the answer', (
      tester,
    ) async {
      _tall(tester);
      final rpc = JoinRpc()
        ..answer('my_circle_bans', [myBanJson()])
        ..answer('submit_ban_appeal', 'a1');
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BanInboxCard(
              ban: MyCircleBan.fromJson(myBanJson()),
              now: () => _now,
            ),
          ),
          rpc,
        ),
      );
      expect(find.text('Permanent'), findsNothing);
      expect(find.textContaining('Permanent'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ban-appeal-open')));
      await tester.pumpAndSettle();
      // Nothing to send until something is written.
      await tester.enterText(
        find.byKey(const ValueKey('ban-appeal-text')),
        'It was a misunderstanding.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ban-appeal-send')));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('submit_ban_appeal').single, {
        'target_circle_id': 'circle-1',
        'appeal_message': 'It was a misunderstanding.',
      });
    });

    testWidgets('an answered appeal shows the note and no button', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BanInboxCard(
              ban: MyCircleBan.fromJson(
                myBanJson(
                  expiresAt: '2099-01-01T10:00:00Z',
                  appealStatus: 'denied',
                  appealNote: 'Come back next month',
                ),
              ),
            ),
          ),
          JoinRpc(),
        ),
      );
      expect(find.text('Your appeal was turned down.'), findsOneWidget);
      expect(find.text('Come back next month'), findsOneWidget);
      expect(find.byKey(const ValueKey('ban-appeal-open')), findsNothing);
    });
  });

  group('the chat card and the audit log', () {
    testWidgets('the alert card carries the numbers', (tester) async {
      final alert = RaidAlert.maybeFromJson({
        'kind': 'raid_alert',
        'joins': 24,
        'new_accounts': 9,
        'hours': 1,
        'until': '2099-01-01T10:00:00Z',
      })!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RaidAlertCard(alert: alert)),
        ),
      );
      expect(find.text('Raid protection locked this circle'), findsOneWidget);
      expect(
        find.text(
          '24 people joined or asked to join within 10 minutes, 9 with a new '
          'account.',
        ),
        findsOneWidget,
      );
      expect(RaidAlert.maybeFromJson({'kind': 'automod_alert'}), isNull);
      expect(RaidAlert.maybeFromJson(null), isNull);
    });

    test('the new audit actions have words and icons', () {
      String summary(String action, [Map<String, dynamic> changes = const {}]) {
        final entry = CircleAuditEntry(
          id: 'x',
          circleId: 'c',
          action: action,
          targetType: 'member',
          targetLabel: 'Nia',
          changes: changes,
          createdAt: _now,
        );
        return circleAuditSummary(entry, null).toPlainText();
      }

      expect(summary('member_unban_auto'), 'The ban on Nia ended');
      expect(summary('thread_lock'), 'Someone locked thread Nia');
      expect(summary('mod_warn'), 'Someone warned Nia');
      expect(summary('ban_appeal_submit'), 'Nia appealed their ban');
      expect(
        summary('raid_lockdown', {'source': 'auto'}),
        'Raid protection locked down joining',
      );
      expect(
        summary('raid_release', {'source': 'expired'}),
        'The lockdown ended by itself',
      );
      expect(
        summary('member_batch_action', {'action': 'ban'}),
        'Someone banned several members at once',
      );
      for (final action in [
        'member_unban_auto',
        'thread_lock',
        'mod_warn',
        'ban_appeal_approve',
        'raid_lockdown',
        'invites_pause',
      ]) {
        expect(circleAuditIcon(action), isNot(Icons.history), reason: action);
      }
      expect(
        CircleAuditActionGroup.of('raid_lockdown'),
        CircleAuditActionGroup.raid,
      );
      expect(CircleAuditActionGroup.of('mod_warn'), CircleAuditActionGroup.mod);
      expect(
        CircleAuditActionGroup.of('ban_appeal_deny'),
        CircleAuditActionGroup.ban,
      );
    });
  });

  test('Chinese words for the audit log and the cards', () {
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    expect(banEndLabel(null), '永久');
    expect(CircleAuditActionGroup.raid.label, '突袭防护');
  });
}
