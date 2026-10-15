import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/mention_picker.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/role_mentions.dart';
import 'package:wecord/features/inbox/inbox_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

const _mods = MentionRole(id: 'role-mods', name: 'Mods', color: 0x3498DB);
const _targets = MentionTargets(canMentionEveryone: true, roles: [_mods]);

Profile _profile(String id, String username) {
  return Profile(
    id: id,
    username: username,
    displayName: username,
    bio: '',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _FakeRoleMentions implements RoleMentionsRepository {
  _FakeRoleMentions(this.targets);

  final MentionTargets targets;

  @override
  Future<MentionTargets> mentionTargets(String conversationId) async => targets;

  @override
  Future<Set<String>> mentionableRoleIds(String circleId) async => const {};

  @override
  Future<void> setRoleMentionable({
    required String roleId,
    required bool mentionable,
  }) async {}
}

void main() {
  group('MessageMention', () {
    test('reads @here and role mentions without a user id', () {
      final here = MessageMention.fromJson({
        'kind': 'here',
        'start': 0,
        'end': 5,
        'display_name': 'here',
      });
      expect(here.isHere, isTrue);
      expect(here.userId, isEmpty);

      final role = MessageMention.fromJson({
        'kind': 'role',
        'role_id': 'role-mods',
        'display_name': 'Mods',
        'color': 0x3498DB,
        'start': 0,
        'end': 5,
      });
      expect(role.isRole, isTrue);
      expect(role.roleId, 'role-mods');
      expect(role.color, 0x3498DB);
    });

    test('sends @here with who is online and roles with their id', () {
      expect(
        const MessageMention.here(start: 0, end: 5, userIds: ['u2']).toJson(),
        {
          'display_name': 'here',
          'start': 0,
          'end': 5,
          'kind': 'here',
          'user_ids': ['u2'],
        },
      );
      expect(
        const MessageMention.role(
          roleId: 'r1',
          displayName: 'Mods',
          start: 1,
          end: 6,
        ).toJson(),
        {
          'display_name': 'Mods',
          'start': 1,
          'end': 6,
          'kind': 'role',
          'role_id': 'r1',
        },
      );
    });
  });

  group('specialMentionCandidates', () {
    test('offers @here and matching roles', () {
      expect(
        specialMentionCandidates(
          _targets,
          '',
          allowHere: true,
        ).map((mention) => mention.token),
        ['@here', '@Mods'],
      );
      expect(
        specialMentionCandidates(
          _targets,
          'mo',
          allowHere: true,
        ).map((mention) => mention.token),
        ['@Mods'],
      );
      expect(
        specialMentionCandidates(
          _targets,
          '',
          allowHere: false,
        ).map((mention) => mention.token),
        ['@Mods'],
      );
      expect(
        specialMentionCandidates(const MentionTargets(), '', allowHere: true),
        isEmpty,
      );
    });
  });

  group('MentionDraft', () {
    test('records picked roles and every @here', () {
      final draft = MentionDraft();
      final controller = TextEditingController(text: 'hey @mo');
      expect(
        draft.insertSpecial(
          controller,
          const SpecialMention.role(roleId: 'role-mods', name: 'Mods'),
        ),
        isTrue,
      );
      expect(controller.text, 'hey @Mods ');

      final body = '${controller.text}and @here, not me@here or @Modsters';
      final mentions = draft.mentionsFor(body, hereUserIds: ['u2', 'u3']);
      expect([for (final mention in mentions) mention.kind], ['role', 'here']);
      expect(mentions[0].start, 4);
      expect(mentions[0].roleId, 'role-mods');
      expect(body.substring(mentions[1].start, mentions[1].end), '@here');
      expect(mentions[1].userIds, ['u2', 'u3']);

      // Without permission (no online list), @here stays text.
      expect(draft.mentionsFor('@here', hereUserIds: null), isEmpty);
    });
  });

  test('inbox reasons include role and @here mentions', () {
    expect(InboxReason.fromJson('mention_role'), InboxReason.mentionRole);
    expect(InboxReason.fromJson('mention_here'), InboxReason.mentionHere);
  });

  testWidgets('role mentions render in the role colour', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MessageMarkdownText(
              body: '@Mods hi',
              mentions: [
                MessageMention.role(
                  roleId: 'role-mods',
                  displayName: 'Mods',
                  color: 0x3498DB,
                  start: 0,
                  end: 5,
                ),
              ],
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    TextStyle? mentionStyle;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == '@Mods') {
        mentionStyle = span.style;
      }
      return true;
    });
    expect(mentionStyle?.color, const Color(0xFF3498DB));
  });

  testWidgets('the composer offers @here and roles and sends them', (
    tester,
  ) async {
    final repository = chat_fakes.FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.group,
          unreadCount: 0,
          title: 'Team',
        ),
      ]
      ..groupDetail = GroupDetail(
        conversationId: 'conversation-1',
        title: 'Team',
        members: [
          GroupMember(profile: _profile('user-1', 'me'), role: 'owner'),
          GroupMember(profile: _profile('user-2', 'grace'), role: 'member'),
          GroupMember(profile: _profile('user-3', 'alan'), role: 'member'),
        ],
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          roleMentionsRepositoryProvider.overrideWithValue(
            _FakeRoleMentions(_targets),
          ),
          composerDraftStoreProvider.overrideWithValue(
            InMemoryComposerDraftStore(),
          ),
          onlineUserIdsProvider.overrideWith(
            (ref) => Stream.value({'user-1', 'user-2'}),
          ),
          settingsRepositoryProvider.overrideWithValue(
            chat_fakes.FakeSettingsRepository(),
          ),
          authRepositoryProvider.overrideWithValue(
            chat_fakes.FakeAuthRepository()
              ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
          ),
        ],
        child: const MaterialApp(
          home: ChatThreadScreen(
            conversationId: 'conversation-1',
            conversationType: ConversationType.group,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final composer = find.byKey(const ValueKey('chat-composer-field'));
    await tester.enterText(composer, '@');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mention-candidate-here')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mention-candidate-role-role-mods')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('mention-candidate-role-role-mods')),
    );
    await tester.pump();
    await tester.enterText(composer, '@Mods and @here');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();

    final mentions = repository.sentMentions;
    expect([for (final mention in mentions) mention.kind], ['role', 'here']);
    // Only other members who are online.
    expect(mentions[1].userIds, ['user-2']);
  });
}
