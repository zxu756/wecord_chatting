# WeCord Social Chat v2 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Social Chat v2 MVP: group chat creation/details, profile settings with avatars, reply/edit message actions, and search.

**Architecture:** Keep Supabase access behind repository/data-source interfaces and use narrow RPCs for sensitive writes. Reuse the existing chat thread for direct and group conversations, extending the message model rather than creating a parallel group thread. Add focused UI surfaces for group creation, settings/profile editing, message reply/edit state, and search.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase Auth/Postgres/Realtime/Storage, Flutter widget tests, SQL migration text tests.

---

## File Structure

- Modify `supabase/migrations/202605180005_social_chat_v2.sql`: add `reply_preview`, group/profile/message RPCs, and avatar bucket policies. Search uses client-side filtering in this MVP.
- Modify `test/supabase/private_chat_schema_test.dart`: assert v2 RPCs and storage policies exist without broad update policies.
- Modify `lib/shared/models/message.dart`: add `ReplyPreview`, `replyPreview`, and serialization.
- Create `lib/shared/models/group.dart`: add `GroupMember` and group detail projection models.
- Modify `lib/shared/models/conversation.dart`: keep summary mapping stable and verify group titles/avatar values.
- Modify `lib/features/chats/chats_repository.dart`: add group creation/detail/member, message reply/edit, avatar storage helper reuse, and thread search APIs.
- Modify `lib/features/chats/chats_screen.dart`: add conversation search field and filtered list behavior.
- Modify `lib/features/chats/chat_thread_screen.dart`: add reply/edit composer state, quoted previews, group detail entry point, and thread search surface.
- Modify `lib/features/contacts/contacts_screen.dart`: add friends filtering and New Group flow.
- Create `lib/features/groups/group_creation_sheet.dart`: self-contained friend picker and group name UI.
- Create `lib/features/groups/group_detail_sheet.dart`: group name/member display and add-member/rename actions.
- Create `lib/features/settings/settings_repository.dart`: profile fetch/update and avatar upload.
- Modify `lib/features/settings/settings_screen.dart`: editable profile form, avatar upload, and sign out.
- Modify tests under `test/features/chats`, `test/features/contacts`, and `test/features/settings` to cover each UI flow.

## Task 1: Backend Contract And Models

**Files:**
- Create: `supabase/migrations/202605180005_social_chat_v2.sql`
- Modify: `test/supabase/private_chat_schema_test.dart`
- Modify: `lib/shared/models/message.dart`
- Create: `lib/shared/models/group.dart`
- Modify: `test/shared/models/private_chat_models_test.dart`

- [ ] **Step 1: Write failing schema tests**

Add tests to `test/supabase/private_chat_schema_test.dart`:

```dart
test('social chat v2 RPCs are narrow and role scoped', () {
  expect(sql, contains('create or replace function public.create_group_conversation'));
  expect(sql, contains('create or replace function public.rename_group_conversation'));
  expect(sql, contains('create or replace function public.add_group_members'));
  expect(sql, contains('create or replace function public.update_current_user_profile'));
  expect(sql, contains('create or replace function public.edit_message'));

  final createGroupBody = functionBody(sql, 'create_group_conversation');
  expect(createGroupBody, contains('auth.uid()'));
  expect(createGroupBody, contains('friendships'));
  expect(createGroupBody, contains("role, 'owner'"));
  expect(createGroupBody, contains("role, 'member'"));

  final renameBody = functionBody(sql, 'rename_group_conversation');
  expect(renameBody, contains("role in ('owner', 'admin')"));

  final editBody = functionBody(sql, 'edit_message');
  expect(editBody, contains('sender_id = auth.uid()'));
  expect(editBody, contains("type = 'text'"));
  expect(editBody, contains('recalled_at is null'));

  final profileBody = functionBody(sql, 'update_current_user_profile');
  expect(profileBody, contains('id = auth.uid()'));
});

test('social chat v2 avoids broad sensitive update policies', () {
  expect(
    sql,
    isNot(contains(RegExp(r'create policy \\w+\\s+on public\\.messages\\s+for update'))),
  );
  expect(
    sql,
    isNot(contains(RegExp(r'create policy \\w+\\s+on public\\.profiles\\s+for update'))),
  );
});

test('profile avatar storage is owner scoped', () {
  expect(sql, contains("insert into storage.buckets (id, name, public)"));
  expect(sql, contains("'profile-avatars'"));
  expect(sql, contains("bucket_id = 'profile-avatars'"));
  expect(sql, contains("(storage.foldername(name))[1] = auth.uid()::text"));
});
```

- [ ] **Step 2: Run schema tests and verify failure**

Run:

```bash
rtk flutter test test/supabase/private_chat_schema_test.dart
```

Expected: failures mentioning missing social chat v2 RPCs and avatar storage policies.

- [ ] **Step 3: Write failing model tests**

Add tests to `test/shared/models/private_chat_models_test.dart`:

```dart
test('ChatMessage parses reply preview and edited timestamp', () {
  final message = ChatMessage.fromJson({
    'id': 'message-1',
    'conversation_id': 'conversation-1',
    'sender_id': 'user-1',
    'type': 'text',
    'body': 'Reply body',
    'attachment': null,
    'reply_to_message_id': 'message-0',
    'reply_preview': {
      'message_id': 'message-0',
      'sender_name': 'Ada',
      'body': 'Original body',
      'type': 'text',
    },
    'created_at': '2026-05-18T00:00:00Z',
    'edited_at': '2026-05-18T00:01:00Z',
    'recalled_at': null,
  });

  expect(message.replyToMessageId, 'message-0');
  expect(message.replyPreview?.senderName, 'Ada');
  expect(message.replyPreview?.body, 'Original body');
  expect(message.editedAt, DateTime.utc(2026, 5, 18, 0, 1));
});
```

- [ ] **Step 4: Run model tests and verify failure**

Run:

```bash
rtk flutter test test/shared/models/private_chat_models_test.dart
```

Expected: failure because `replyPreview` and `ReplyPreview` are not implemented.

- [ ] **Step 5: Implement migration**

Create `supabase/migrations/202605180005_social_chat_v2.sql` with:

```sql
alter table public.messages
  add column if not exists reply_preview jsonb;

create or replace function public.create_group_conversation(
  group_title text,
  member_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_title text;
  member_id uuid;
  new_conversation_id uuid;
begin
  trimmed_title = nullif(trim(group_title), '');
  if trimmed_title is null then
    raise exception 'Group name is required' using errcode = '23514';
  end if;

  if coalesce(array_length(member_ids, 1), 0) < 2 then
    raise exception 'Choose at least two friends' using errcode = '23514';
  end if;

  foreach member_id in array member_ids loop
    if member_id = auth.uid() then
      raise exception 'Group members must be friends' using errcode = '42501';
    end if;

    if not exists (
      select 1
      from public.friendships f
      where (f.user_low_id = least(auth.uid(), member_id)
        and f.user_high_id = greatest(auth.uid(), member_id))
    ) then
      raise exception 'Group members must be friends' using errcode = '42501';
    end if;
  end loop;

  insert into public.conversations (type, title)
  values ('group', trimmed_title)
  returning id into new_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (new_conversation_id, auth.uid(), 'owner');

  insert into public.conversation_members (conversation_id, user_id, role)
  select new_conversation_id, distinct_member_id, 'member'
  from unnest(member_ids) as distinct_member_id
  where distinct_member_id <> auth.uid()
  on conflict (conversation_id, user_id) do nothing;

  return new_conversation_id;
end;
$$;

create or replace function public.rename_group_conversation(
  target_conversation_id uuid,
  group_title text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_id uuid;
begin
  update public.conversations c
  set title = nullif(trim(group_title), '')
  where c.id = target_conversation_id
    and c.type = 'group'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.id
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'admin')
    )
    and nullif(trim(group_title), '') is not null
  returning c.id into updated_id;

  if updated_id is null then
    raise exception 'Group cannot be renamed' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.add_group_members(
  target_conversation_id uuid,
  member_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  member_id uuid;
begin
  if not exists (
    select 1
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
    where cm.conversation_id = target_conversation_id
      and cm.user_id = auth.uid()
      and cm.role in ('owner', 'admin')
      and c.type = 'group'
  ) then
    raise exception 'Cannot add group members' using errcode = '42501';
  end if;

  foreach member_id in array member_ids loop
    if not exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(auth.uid(), member_id)
        and f.user_high_id = greatest(auth.uid(), member_id)
    ) then
      raise exception 'Group members must be friends' using errcode = '42501';
    end if;
  end loop;

  insert into public.conversation_members (conversation_id, user_id, role)
  select target_conversation_id, distinct_member_id, 'member'
  from unnest(member_ids) as distinct_member_id
  where distinct_member_id <> auth.uid()
  on conflict (conversation_id, user_id) do nothing;
end;
$$;

create or replace function public.update_current_user_profile(
  display_name text,
  bio text,
  avatar_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set display_name = nullif(trim(display_name), ''),
      bio = coalesce(bio, ''),
      avatar_url = nullif(trim(avatar_url), '')
  where id = auth.uid()
    and nullif(trim(display_name), '') is not null;

  if not found then
    raise exception 'Profile cannot be updated' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.edit_message(
  target_message_id uuid,
  body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  edited_id uuid;
begin
  update public.messages m
  set body = trim(body),
      edited_at = now()
  where m.id = target_message_id
    and m.sender_id = auth.uid()
    and m.type = 'text'
    and m.recalled_at is null
    and char_length(trim(body)) > 0
    and public.is_current_user_conversation_member(m.conversation_id)
  returning m.id into edited_id;

  if edited_id is null then
    raise exception 'Message cannot be edited' using errcode = '42501';
  end if;
end;
$$;

insert into storage.buckets (id, name, public)
values ('profile-avatars', 'profile-avatars', false)
on conflict (id) do nothing;

create policy profile_avatars_select_authenticated
  on storage.objects for select
  to authenticated
  using (bucket_id = 'profile-avatars');

create policy profile_avatars_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [ ] **Step 6: Implement message and group models**

In `lib/shared/models/message.dart`, add:

```dart
class ReplyPreview {
  const ReplyPreview({
    required this.messageId,
    required this.senderName,
    required this.body,
    required this.type,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> json) {
    return ReplyPreview(
      messageId: json['message_id'] as String,
      senderName: json['sender_name'] as String,
      body: json['body'] as String,
      type: MessageType.fromJson(json['type'] as String),
    );
  }

  final String messageId;
  final String senderName;
  final String body;
  final MessageType type;

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'sender_name': senderName,
      'body': body,
      'type': type.toJson(),
    };
  }
}
```

Add `replyPreview` to `ChatMessage`, parse `json['reply_preview']`, include it in `toJson`, and support it in `copyWith`.

Create `lib/shared/models/group.dart`:

```dart
import 'package:wecord/shared/models/profile.dart';

class GroupMember {
  const GroupMember({required this.profile, required this.role});

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      role: json['role'] as String,
    );
  }

  final Profile profile;
  final String role;
}

class GroupDetail {
  const GroupDetail({
    required this.conversationId,
    required this.title,
    required this.members,
  });

  final String conversationId;
  final String title;
  final List<GroupMember> members;
}
```

- [ ] **Step 7: Run model and schema tests**

Run:

```bash
rtk dart format lib/shared/models/message.dart lib/shared/models/group.dart test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
rtk flutter test test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
```

Expected: both test files pass.

- [ ] **Step 8: Commit backend contract and models**

Run:

```bash
rtk git add supabase/migrations/202605180005_social_chat_v2.sql test/supabase/private_chat_schema_test.dart lib/shared/models/message.dart lib/shared/models/group.dart test/shared/models/private_chat_models_test.dart
rtk git commit -m "feat: add social chat v2 backend contract"
```

## Task 2: Repository APIs For Groups, Profile, Reply, Edit, And Search

**Files:**
- Modify: `lib/features/chats/chats_repository.dart`
- Create: `lib/features/settings/settings_repository.dart`
- Modify: `test/features/chats/chats_repository_test.dart`
- Create: `test/features/settings/settings_repository_test.dart`

- [ ] **Step 1: Write failing chat repository tests**

Add to `test/features/chats/chats_repository_test.dart`:

```dart
test('createGroupConversation calls the group creation RPC', () async {
  final dataSource = FakeChatsDataSource()..rpcResult = 'group-1';
  final repository = SupabaseChatsRepository.withDataSource(
    dataSource,
    currentUserId: () => 'user-1',
  );

  final conversationId = await repository.createGroupConversation(
    title: 'Study Group',
    memberIds: ['user-2', 'user-3'],
  );

  expect(conversationId, 'group-1');
  expect(dataSource.rpcCalls.single.params, {
    'group_title': 'Study Group',
    'member_ids': ['user-2', 'user-3'],
  });
});

test('sendTextMessage can include reply preview', () async {
  final dataSource = FakeChatsDataSource();
  final repository = SupabaseChatsRepository.withDataSource(
    dataSource,
    currentUserId: () => 'user-1',
  );

  await repository.sendTextMessage(
    conversationId: 'conversation-1',
    body: 'Reply',
    replyToMessageId: 'message-1',
    replyPreview: const ReplyPreview(
      messageId: 'message-1',
      senderName: 'Ada',
      body: 'Original',
      type: MessageType.text,
    ),
  );

  expect(dataSource.insertedMessages.single['reply_to_message_id'], 'message-1');
  expect(dataSource.insertedMessages.single['reply_preview'], {
    'message_id': 'message-1',
    'sender_name': 'Ada',
    'body': 'Original',
    'type': 'text',
  });
});

test('editMessage calls the edit RPC', () async {
  final dataSource = FakeChatsDataSource();
  final repository = SupabaseChatsRepository.withDataSource(
    dataSource,
    currentUserId: () => 'user-1',
  );

  await repository.editMessage(messageId: 'message-1', body: 'Updated');

  expect(dataSource.rpcCalls.single.functionName, 'edit_message');
  expect(dataSource.rpcCalls.single.params, {
    'target_message_id': 'message-1',
    'body': 'Updated',
  });
});
```

- [ ] **Step 2: Write failing settings repository tests**

Create `test/features/settings/settings_repository_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/settings/settings_repository.dart';

void main() {
  test('updateProfile calls scoped profile RPC', () async {
    final dataSource = FakeSettingsDataSource();
    final repository = SupabaseSettingsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.updateProfile(
      displayName: 'Ada',
      bio: 'Math',
      avatarUrl: 'profile-avatars/user-1/avatar.png',
    );

    expect(dataSource.rpcCalls.single.functionName, 'update_current_user_profile');
    expect(dataSource.rpcCalls.single.params, {
      'display_name': 'Ada',
      'bio': 'Math',
      'avatar_url': 'profile-avatars/user-1/avatar.png',
    });
  });

  test('uploadAvatar stores the file under the current user folder', () async {
    final dataSource = FakeSettingsDataSource();
    final repository = SupabaseSettingsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => 'seed',
    );

    final path = await repository.uploadAvatar(
      fileName: 'Face Shot.PNG',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(path, 'user-1/seed-face-shot.png');
    expect(dataSource.uploads.single.path, path);
  });
}
```

- [ ] **Step 3: Run repository tests and verify failure**

Run:

```bash
rtk flutter test test/features/chats/chats_repository_test.dart test/features/settings/settings_repository_test.dart
```

Expected: failures because repository methods and settings repository do not exist.

- [ ] **Step 4: Extend chat repository interfaces and implementation**

In `lib/features/chats/chats_repository.dart`, extend `ChatsRepository`:

```dart
Future<String> createGroupConversation({
  required String title,
  required List<String> memberIds,
});

Future<void> renameGroupConversation({
  required String conversationId,
  required String title,
});

Future<void> addGroupMembers({
  required String conversationId,
  required List<String> memberIds,
});

Future<void> editMessage({
  required String messageId,
  required String body,
});

List<ConversationSummary> searchConversations(
  List<ConversationSummary> conversations,
  String query,
);

List<ChatMessage> searchMessages(List<ChatMessage> messages, String query);
```

Change `sendTextMessage` signature:

```dart
Future<void> sendTextMessage({
  required String conversationId,
  required String body,
  String? replyToMessageId,
  ReplyPreview? replyPreview,
});
```

Implement:

```dart
@override
Future<String> createGroupConversation({
  required String title,
  required List<String> memberIds,
}) async {
  final conversationId = await _dataSource.rpc('create_group_conversation', {
    'group_title': title.trim(),
    'member_ids': memberIds,
  });
  return conversationId as String;
}

@override
Future<void> editMessage({
  required String messageId,
  required String body,
}) async {
  await _dataSource.rpc('edit_message', {
    'target_message_id': messageId,
    'body': body.trim(),
  });
}
```

Update `sendTextMessage` insert map to include `reply_to_message_id` and `reply_preview` when provided.

- [ ] **Step 5: Create settings repository**

Create `lib/features/settings/settings_repository.dart` with:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/profile.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SupabaseSettingsRepository(ref.watch(supabaseClientProvider));
});

abstract interface class SettingsRepository {
  Future<Profile> currentProfile();
  Future<void> updateProfile({
    required String displayName,
    required String bio,
    required String? avatarUrl,
  });
  Future<String> uploadAvatar({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  });
}
```

Implement `SupabaseSettingsRepository`, `SettingsDataSource`, `SupabaseSettingsDataSource`, `uploadBinary`, `rpc`, and a `_safeFileName` helper matching `ChatsRepository` behavior. Use bucket `profile-avatars` and path `$currentUserId/${seed}-${safeName}`.

- [ ] **Step 6: Update fakes in existing tests**

Every fake `ChatsRepository` in tests must implement:

```dart
@override
Future<String> createGroupConversation({
  required String title,
  required List<String> memberIds,
}) async => 'group-1';

@override
Future<void> renameGroupConversation({
  required String conversationId,
  required String title,
}) async {}

@override
Future<void> addGroupMembers({
  required String conversationId,
  required List<String> memberIds,
}) async {}

@override
Future<void> editMessage({
  required String messageId,
  required String body,
}) async {}

@override
List<ConversationSummary> searchConversations(
  List<ConversationSummary> conversations,
  String query,
) => conversations;

@override
List<ChatMessage> searchMessages(List<ChatMessage> messages, String query) {
  return messages;
}
```

- [ ] **Step 7: Run repository tests**

Run:

```bash
rtk dart format lib/features/chats/chats_repository.dart lib/features/settings/settings_repository.dart test/features/chats/chats_repository_test.dart test/features/settings/settings_repository_test.dart
rtk flutter test test/features/chats/chats_repository_test.dart test/features/settings/settings_repository_test.dart
```

Expected: repository tests pass.

- [ ] **Step 8: Commit repository layer**

Run:

```bash
rtk git add lib/features/chats/chats_repository.dart lib/features/settings/settings_repository.dart test/features/chats/chats_repository_test.dart test/features/settings/settings_repository_test.dart
rtk git commit -m "feat: add social chat repository APIs"
```

## Task 3: Group Chat MVP UI

**Files:**
- Create: `lib/features/groups/group_creation_sheet.dart`
- Create: `lib/features/groups/group_detail_sheet.dart`
- Modify: `lib/features/contacts/contacts_screen.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `test/features/contacts/contacts_screen_test.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`

- [ ] **Step 1: Write failing contacts widget test**

Add to `test/features/contacts/contacts_screen_test.dart`:

```dart
testWidgets('creates a group conversation from friends', (tester) async {
  final contactsRepository = FakeContactsRepository()
    ..friends = [
      _profile(id: 'friend-1', username: 'ada', displayName: 'Ada'),
      _profile(id: 'friend-2', username: 'grace', displayName: 'Grace'),
    ];
  final chatsRepository = FakeChatsRepository();

  await tester.pumpWidget(
    _app(contactsRepository, chatsRepository: chatsRepository),
  );
  await tester.pump();

  await tester.tap(find.widgetWithText(FilledButton, 'New Group'));
  await tester.pumpAndSettle();
  await tester.enterText(find.bySemanticsLabel('Group name'), 'Study Group');
  await tester.tap(find.text('Ada'));
  await tester.tap(find.text('Grace'));
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();

  expect(chatsRepository.createdGroups.single.title, 'Study Group');
  expect(chatsRepository.createdGroups.single.memberIds, ['friend-1', 'friend-2']);
});
```

- [ ] **Step 2: Write failing group detail widget test**

Add to `test/features/chats/chat_thread_screen_test.dart`:

```dart
testWidgets('opens group details from the chat app bar', (tester) async {
  final repository = FakeChatsRepository()
    ..messages = []
    ..groupMembers = [
      _profile(id: 'user-1', username: 'ada', displayName: 'Ada'),
      _profile(id: 'user-2', username: 'grace', displayName: 'Grace'),
    ];

  await tester.pumpWidget(_app(repository, currentUserId: 'user-1'));
  await tester.pump();

  await tester.tap(find.byTooltip('Group details'));
  await tester.pumpAndSettle();

  expect(find.text('Group members'), findsOneWidget);
  expect(find.text('Ada'), findsOneWidget);
  expect(find.text('Grace'), findsOneWidget);
});
```

- [ ] **Step 3: Run widget tests and verify failure**

Run:

```bash
rtk flutter test test/features/contacts/contacts_screen_test.dart test/features/chats/chat_thread_screen_test.dart
```

Expected: failures because group UI does not exist.

- [ ] **Step 4: Create group creation sheet**

Create `lib/features/groups/group_creation_sheet.dart` with a `ConsumerStatefulWidget` that accepts `List<Profile> friends`, tracks selected ids, validates `groupName.trim().isNotEmpty && selectedIds.length >= 2`, calls `chatsRepositoryProvider.createGroupConversation`, invalidates `conversationsProvider`, and returns `GroupCreationResult(conversationId, title)` via `Navigator.pop`.

Use labels:
- `Group name`
- `Create`
- `Choose at least two friends.`

- [ ] **Step 5: Add New Group entry point**

In `lib/features/contacts/contacts_screen.dart`, add a `FilledButton.icon` above friends:

```dart
FilledButton.icon(
  onPressed: friends.length < 2
      ? null
      : () async {
          final result = await showModalBottomSheet<GroupCreationResult>(
            context: context,
            isScrollControlled: true,
            builder: (context) => GroupCreationSheet(friends: friends),
          );
          if (result == null || !context.mounted) {
            return;
          }
          context.go('${ChatsScreen.path}/${result.conversationId}', extra: result.title);
        },
  icon: const Icon(Icons.group_add_outlined),
  label: const Text('New Group'),
)
```

- [ ] **Step 6: Create group detail sheet**

Create `lib/features/groups/group_detail_sheet.dart` with title `Group members`, member `ListTile`s, a rename button, and an add members button. For MVP, source members from a repository method returning `GroupDetail`; if only profile data is available in fakes, map profiles to member rows with role `member`.

- [ ] **Step 7: Add app bar group detail action**

In `lib/features/chats/chat_thread_screen.dart`, when the thread title is not a direct friend title or when `ConversationType.group` becomes available through thread data, show:

```dart
IconButton(
  tooltip: 'Group details',
  icon: const Icon(Icons.info_outline),
  onPressed: () {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => GroupDetailSheet(conversationId: widget.conversationId),
    );
  },
)
```

- [ ] **Step 8: Run group UI tests**

Run:

```bash
rtk dart format lib/features/groups/group_creation_sheet.dart lib/features/groups/group_detail_sheet.dart lib/features/contacts/contacts_screen.dart lib/features/chats/chat_thread_screen.dart test/features/contacts/contacts_screen_test.dart test/features/chats/chat_thread_screen_test.dart
rtk flutter test test/features/contacts/contacts_screen_test.dart test/features/chats/chat_thread_screen_test.dart
```

Expected: contacts and chat thread tests pass.

- [ ] **Step 9: Commit group UI**

Run:

```bash
rtk git add lib/features/groups/group_creation_sheet.dart lib/features/groups/group_detail_sheet.dart lib/features/contacts/contacts_screen.dart lib/features/chats/chat_thread_screen.dart test/features/contacts/contacts_screen_test.dart test/features/chats/chat_thread_screen_test.dart
rtk git commit -m "feat: add group chat mvp"
```

## Task 4: Settings Profile And Avatar MVP

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/features/contacts/contacts_screen.dart`
- Modify: `lib/features/chats/chats_screen.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Create: `test/features/settings/settings_screen_test.dart`
- Modify: existing contacts/chats widget tests for avatar rendering.

- [ ] **Step 1: Write failing settings screen tests**

Create `test/features/settings/settings_screen_test.dart`:

```dart
testWidgets('edits display name and bio', (tester) async {
  final repository = FakeSettingsRepository(profile: _profile());
  await tester.pumpWidget(_app(repository));
  await tester.pump();

  await tester.enterText(find.bySemanticsLabel('Display name'), 'Ada L.');
  await tester.enterText(find.bySemanticsLabel('Bio'), 'Computing notes');
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pump();

  expect(repository.updatedDisplayName, 'Ada L.');
  expect(repository.updatedBio, 'Computing notes');
});

testWidgets('signs out from settings', (tester) async {
  final authRepository = FakeAuthRepository();
  await tester.pumpWidget(_app(FakeSettingsRepository(profile: _profile()), authRepository: authRepository));
  await tester.pump();

  await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
  await tester.pump();

  expect(authRepository.signedOut, isTrue);
});
```

- [ ] **Step 2: Run settings screen tests and verify failure**

Run:

```bash
rtk flutter test test/features/settings/settings_screen_test.dart
```

Expected: failure because settings UI and provider wiring are not implemented.

- [ ] **Step 3: Implement settings screen form**

Replace placeholder `SettingsScreen` with a `ConsumerStatefulWidget` that:
- watches `currentProfileProvider`
- renders `CircleAvatar`
- renders `TextField` labels `Display name` and `Bio`
- renders read-only username text
- calls `settingsRepositoryProvider.updateProfile`
- calls `authRepositoryProvider.signOut`

Use button labels:
- `Save`
- `Change avatar`
- `Sign out`

- [ ] **Step 4: Add avatar upload interaction**

Reuse `imagePickerServiceProvider.pickImage()` to select an image, then call:

```dart
final avatarPath = await ref.read(settingsRepositoryProvider).uploadAvatar(
  fileName: image.fileName,
  mimeType: image.mimeType,
  bytes: image.bytes,
);
```

Store the returned path in local form state and pass it as `avatarUrl` on save.

- [ ] **Step 5: Add avatar rendering to shared list surfaces**

In contacts/chats/thread list tiles, use:

```dart
CircleAvatar(
  backgroundImage: profile.avatarUrl == null ? null : NetworkImage(profile.avatarUrl!),
  child: profile.avatarUrl == null ? Text(profile.displayName.characters.first.toUpperCase()) : null,
)
```

For paths that are not public URLs, keep initials in MVP unless a signed URL helper exists in that repository path.

- [ ] **Step 6: Run settings and affected widget tests**

Run:

```bash
rtk dart format lib/features/settings/settings_screen.dart lib/features/contacts/contacts_screen.dart lib/features/chats/chats_screen.dart lib/features/chats/chat_thread_screen.dart test/features/settings/settings_screen_test.dart
rtk flutter test test/features/settings/settings_screen_test.dart test/features/contacts/contacts_screen_test.dart test/features/chats/chats_screen_test.dart test/features/chats/chat_thread_screen_test.dart
```

Expected: all listed tests pass.

- [ ] **Step 7: Commit settings/profile MVP**

Run:

```bash
rtk git add lib/features/settings/settings_screen.dart lib/features/contacts/contacts_screen.dart lib/features/chats/chats_screen.dart lib/features/chats/chat_thread_screen.dart test/features/settings/settings_screen_test.dart
rtk git commit -m "feat: add profile settings mvp"
```

## Task 5: Reply And Edit Message MVP

**Files:**
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`
- Modify: `test/features/chats/chats_repository_test.dart`

- [ ] **Step 1: Write failing reply widget test**

Add to `test/features/chats/chat_thread_screen_test.dart`:

```dart
testWidgets('replies to a message from the action menu', (tester) async {
  final repository = FakeChatsRepository()
    ..messages = [_message(id: 'message-1', body: 'Original', senderId: 'user-2')];

  await tester.pumpWidget(_app(repository, currentUserId: 'user-1'));
  await tester.pump();

  await tester.longPress(find.text('Original'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Reply'));
  await tester.pumpAndSettle();

  expect(find.text('Replying to Original'), findsOneWidget);
  await tester.enterText(find.byType(TextField).last, 'My reply');
  await tester.tap(find.byTooltip('Send message'));
  await tester.pump();

  expect(repository.sentReplyToMessageId, 'message-1');
});
```

- [ ] **Step 2: Write failing edit widget test**

Add:

```dart
testWidgets('edits an outgoing text message from the action menu', (tester) async {
  final repository = FakeChatsRepository()
    ..messages = [_message(id: 'message-1', body: 'Before', senderId: 'user-1')];

  await tester.pumpWidget(_app(repository, currentUserId: 'user-1'));
  await tester.pump();

  await tester.longPress(find.text('Before'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, 'After');
  await tester.tap(find.byTooltip('Save edit'));
  await tester.pump();

  expect(repository.editedMessageIds, ['message-1']);
  expect(repository.editedBodies, ['After']);
});
```

- [ ] **Step 3: Run chat thread tests and verify failure**

Run:

```bash
rtk flutter test test/features/chats/chat_thread_screen_test.dart
```

Expected: failures because reply/edit actions are not available.

- [ ] **Step 4: Add reply state**

In `_ChatThreadScreenState`, add:

```dart
ChatMessage? _replyingTo;
```

Add `onReply` to `_MessageBubble`. In the bottom sheet, show `Reply` for non-recalled messages. Above `_Composer`, render:

```dart
if (_replyingTo != null)
  ListTile(
    title: Text('Replying to ${_replyingTo!.body.isEmpty ? 'image' : _replyingTo!.body}'),
    trailing: IconButton(
      tooltip: 'Cancel reply',
      icon: const Icon(Icons.close),
      onPressed: () => setState(() => _replyingTo = null),
    ),
  )
```

When sending text, pass `replyToMessageId` and a `ReplyPreview` built from `_replyingTo`, then clear `_replyingTo` after success.

- [ ] **Step 5: Render reply previews**

In `_MessageContent`, before text/image content, render:

```dart
if (message.replyPreview != null)
  Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outline)),
    ),
    child: Text('${message.replyPreview!.senderName}: ${message.replyPreview!.body}'),
  )
```

- [ ] **Step 6: Add edit state and save action**

In `_ChatThreadScreenState`, add:

```dart
ChatMessage? _editingMessage;
```

When editing starts, set `_editingMessage` and set `_composerController.text = message.body`. If `_editingMessage != null`, send button tooltip becomes `Save edit` and send calls `editMessage` instead of `sendTextMessage`.

- [ ] **Step 7: Render edited marker**

In `_MessageBubble`, render `edited` beside read receipt when `message.editedAt != null && message.recalledAt == null`.

- [ ] **Step 8: Run reply/edit tests**

Run:

```bash
rtk dart format lib/features/chats/chat_thread_screen.dart test/features/chats/chat_thread_screen_test.dart
rtk flutter test test/features/chats/chat_thread_screen_test.dart
```

Expected: chat thread tests pass.

- [ ] **Step 9: Commit reply/edit MVP**

Run:

```bash
rtk git add lib/features/chats/chat_thread_screen.dart test/features/chats/chat_thread_screen_test.dart test/features/chats/chats_repository_test.dart
rtk git commit -m "feat: add reply and edit messages"
```

## Task 6: Search MVP

**Files:**
- Modify: `lib/features/chats/chats_screen.dart`
- Modify: `lib/features/contacts/contacts_screen.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `test/features/chats/chats_screen_test.dart`
- Modify: `test/features/contacts/contacts_screen_test.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`

- [ ] **Step 1: Write failing chats search test**

Add to `test/features/chats/chats_screen_test.dart`:

```dart
testWidgets('filters conversations by search query', (tester) async {
  final repository = FakeChatsRepository()
    ..conversations = [
      _conversation(id: 'conversation-1', title: 'Ada', lastMessageBody: 'Math notes'),
      _conversation(id: 'conversation-2', title: 'Grace', lastMessageBody: 'Compiler'),
    ];

  await tester.pumpWidget(_app(repository));
  await tester.pump();

  await tester.enterText(find.bySemanticsLabel('Search chats'), 'math');
  await tester.pump();

  expect(find.text('Ada'), findsOneWidget);
  expect(find.text('Grace'), findsNothing);
});
```

- [ ] **Step 2: Write failing thread search test**

Add to `test/features/chats/chat_thread_screen_test.dart`:

```dart
testWidgets('searches messages in the current thread', (tester) async {
  final repository = FakeChatsRepository()
    ..messages = [
      _message(id: 'message-1', body: 'Lunch tomorrow', senderId: 'user-2'),
      _message(id: 'message-2', body: 'Project notes', senderId: 'user-1'),
    ];

  await tester.pumpWidget(_app(repository, currentUserId: 'user-1'));
  await tester.pump();

  await tester.tap(find.byTooltip('Search messages'));
  await tester.pumpAndSettle();
  await tester.enterText(find.bySemanticsLabel('Search messages'), 'project');
  await tester.pump();

  expect(find.text('Project notes'), findsWidgets);
  expect(find.text('Lunch tomorrow'), findsOneWidget);
});
```

- [ ] **Step 3: Run search tests and verify failure**

Run:

```bash
rtk flutter test test/features/chats/chats_screen_test.dart test/features/chats/chat_thread_screen_test.dart test/features/contacts/contacts_screen_test.dart
```

Expected: failures because search fields do not exist.

- [ ] **Step 4: Add Chats search field**

In `lib/features/chats/chats_screen.dart`, add a `StateProvider.autoDispose<String>` for query and a `TextField` with label `Search chats`. Filter conversations through `repository.searchConversations(conversations, query)`.

- [ ] **Step 5: Add Contacts friends filter**

In `lib/features/contacts/contacts_screen.dart`, use the existing search query or add a friends-specific field labeled `Search friends`. Filter `friends` by display name or username using lowercase `contains`.

- [ ] **Step 6: Add thread search surface**

In `lib/features/chats/chat_thread_screen.dart`, add an app bar icon:

```dart
IconButton(
  tooltip: 'Search messages',
  icon: const Icon(Icons.search),
  onPressed: () => setState(() => _isSearchingMessages = true),
)
```

When searching, show `TextField(labelText: 'Search messages')` above the message list and compute matches with `repository.searchMessages(messages, query)`. Display a small result count such as `1 result`.

- [ ] **Step 7: Run search tests**

Run:

```bash
rtk dart format lib/features/chats/chats_screen.dart lib/features/contacts/contacts_screen.dart lib/features/chats/chat_thread_screen.dart test/features/chats/chats_screen_test.dart test/features/contacts/contacts_screen_test.dart test/features/chats/chat_thread_screen_test.dart
rtk flutter test test/features/chats/chats_screen_test.dart test/features/contacts/contacts_screen_test.dart test/features/chats/chat_thread_screen_test.dart
```

Expected: all listed tests pass.

- [ ] **Step 8: Commit search MVP**

Run:

```bash
rtk git add lib/features/chats/chats_screen.dart lib/features/contacts/contacts_screen.dart lib/features/chats/chat_thread_screen.dart test/features/chats/chats_screen_test.dart test/features/contacts/contacts_screen_test.dart test/features/chats/chat_thread_screen_test.dart
rtk git commit -m "feat: add chat and contact search"
```

## Task 7: Full Verification, Migration Push, And GitHub Push

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README milestone summary**

Update `README.md` milestone text to include group chats, profile settings/avatar, reply/edit, and search.

- [ ] **Step 2: Run full verification**

Run:

```bash
rtk dart format lib test
rtk flutter analyze
rtk flutter test
```

Expected:
- `flutter analyze` reports `No issues found`.
- `flutter test` reports all tests passed.

- [ ] **Step 3: Push Supabase migration**

Run:

```bash
rtk supabase db push
```

Expected: Supabase prompts for `202605180005_social_chat_v2.sql`; answer `y`; command finishes successfully.

- [ ] **Step 4: Commit README**

Run:

```bash
rtk git add README.md
rtk git commit -m "docs: update social chat v2 milestone"
```

- [ ] **Step 5: Push GitHub branch**

Run:

```bash
rtk git push
```

Expected: `wecord-foundation` pushes to `origin/wecord-foundation`.

## Self-Review

Spec coverage:
- Group chat MVP is covered by Tasks 1, 2, and 3.
- Profile/settings/avatar is covered by Tasks 1, 2, and 4.
- Reply/edit message actions are covered by Tasks 1, 2, and 5.
- Search MVP is covered by Tasks 2 and 6.
- Verification and deployment are covered by Task 7.

Placeholder scan:
- The plan contains no placeholder markers, vague test instructions, or unnamed files.
- Each task includes exact paths, test commands, expected outcomes, and commit commands.

Type consistency:
- `ReplyPreview`, `GroupDetail`, `GroupMember`, `createGroupConversation`, `editMessage`, and `updateProfile` are introduced before later tasks consume them.
- `sendTextMessage` signature is changed once in Task 2 and reused by Task 5.
