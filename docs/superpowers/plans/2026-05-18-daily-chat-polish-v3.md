# WeCord Daily Chat Polish v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make WeCord feel more like a daily-driver chat app by adding contact aliases, voice messages, message forwarding, and global message search.

**Architecture:** Keep sensitive writes behind narrow Supabase RPCs and keep binary upload logic inside the chats repository. Extend the existing message model rather than creating a second message pipeline, then add focused UI surfaces around the current contacts, chats list, and thread screens. Treat this as the final “daily chat fundamentals” milestone before moving on to lighter social features such as moments and shared albums.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase Auth/Postgres/Realtime/Storage, `record`, `just_audio`, Flutter widget/unit tests, SQL migration text tests.

---

## Scope

### In Scope

- Per-user friend aliases / remarks that appear anywhere a friend name is rendered.
- Voice message recording, upload, playback, and `[Voice]` conversation previews.
- Forwarding existing text, image, and voice messages into another direct/group conversation.
- Global message search across conversations, with result rows that jump into the matched thread.

### Out Of Scope

- Reactions, stickers, disappearing messages, threads, moments, circles, channels, bots, and remote push notifications.
- Audio transcription and waveform editing.
- Multi-target forwarding and external-share forwarding.
- Search across recalled messages or attachments by OCR/transcription.

## Roadmap Position

1. **Current plan: Daily Chat Polish v3**
   - Aliases
   - Voice messages
   - Forwarding
   - Global search
2. **Next milestone: Familiar Social v4**
   - Moments feed
   - Shared albums
   - Lightweight reactions/comments
   - Event / poll primitives for friend groups
3. **Later milestone: Discord Layer v5**
   - Circles
   - Channels
   - Threads
   - Roles and channel-level notification controls

## File Structure

- Create `supabase/migrations/202605180010_daily_chat_polish_v3.sql`: contact aliases, forward metadata, voice storage bucket, and global search RPCs.
- Modify `test/supabase/private_chat_schema_test.dart`: assert narrow alias/forward/search RPCs and voice storage policy shape.
- Modify `lib/shared/models/profile.dart`: add a nullable `alias` projection for friend display names.
- Modify `lib/shared/models/message.dart`: add `ForwardPreview`, `VoiceAttachment`, and helper accessors.
- Modify `test/shared/models/private_chat_models_test.dart`: cover alias, voice attachment, and forward preview parsing.
- Modify `lib/features/contacts/contacts_repository.dart`: add alias read/write APIs.
- Create `lib/features/contacts/contact_alias_sheet.dart`: focused alias editor.
- Modify `lib/features/contacts/contacts_screen.dart`: show aliases and expose alias editing from friend rows.
- Modify `lib/features/chats/chats_repository.dart`: add voice upload/send, forward, and global search APIs.
- Create `lib/features/chats/voice_message_recorder.dart`: recording state boundary around `record`.
- Create `lib/features/chats/voice_message_player.dart`: playback widget boundary around `just_audio`.
- Create `lib/features/chats/message_forward_sheet.dart`: target picker and submit flow.
- Create `lib/features/chats/global_message_search_screen.dart`: cross-chat search UI.
- Modify `lib/features/chats/chats_screen.dart`: add global search entry point and voice preview rendering.
- Modify `lib/features/chats/chat_thread_screen.dart`: add voice composer control, voice bubble rendering, and Forward message action.
- Modify `lib/shared/navigation/app_router.dart`: add the global search route.
- Modify `pubspec.yaml`, `pubspec.lock`, `ios/Runner/Info.plist`, `macos/Runner/Info.plist`, and macOS entitlements: audio package dependencies and microphone permissions.
- Add focused tests under `test/features/contacts` and `test/features/chats`.

## Task 1: Backend Contract And Domain Models

**Files:**
- Create: `supabase/migrations/202605180010_daily_chat_polish_v3.sql`
- Modify: `test/supabase/private_chat_schema_test.dart`
- Modify: `lib/shared/models/profile.dart`
- Modify: `lib/shared/models/message.dart`
- Modify: `test/shared/models/private_chat_models_test.dart`

- [ ] **Step 1: Write failing schema tests**

Add to `test/supabase/private_chat_schema_test.dart`:

```dart
test('daily chat polish adds narrow alias forward and search contracts', () {
  final sql = allMigrationSql();

  expect(sql, contains('create table if not exists public.contact_aliases'));
  expect(sql, contains('create or replace function public.set_contact_alias'));
  expect(sql, contains('create or replace function public.list_friends_with_aliases'));
  expect(sql, contains('create or replace function public.forward_message'));
  expect(sql, contains('create or replace function public.search_messages'));

  final aliasBody = functionBody(sql, 'set_contact_alias');
  expect(aliasBody, contains('auth.uid()'));
  expect(aliasBody, contains('friendships'));

  final forwardBody = functionBody(sql, 'forward_message');
  expect(forwardBody, contains('public.is_current_user_conversation_member'));
  expect(forwardBody, contains('forwarded_from'));

  final searchBody = functionBody(sql, 'search_messages');
  expect(searchBody, contains('websearch_to_tsquery'));
  expect(searchBody, contains('public.is_current_user_conversation_member'));
});

test('daily chat polish scopes voice storage to conversation members', () {
  final sql = allMigrationSql();

  expect(sql, contains("'voice-messages'"));
  expect(sql, contains('voice_messages_select_member'));
  expect(sql, contains('voice_messages_insert_member'));
});
```

- [ ] **Step 2: Write failing model tests**

Add to `test/shared/models/private_chat_models_test.dart`:

```dart
test('Profile prefers alias when present', () {
  final profile = Profile.fromJson({
    'id': 'user-2',
    'username': 'ada',
    'display_name': 'Ada Lovelace',
    'alias': 'Ada L.',
    'avatar_url': null,
    'bio': '',
    'created_at': '2026-05-18T00:00:00Z',
    'updated_at': '2026-05-18T00:00:00Z',
  });

  expect(profile.alias, 'Ada L.');
  expect(profile.displayLabel, 'Ada L.');
});

test('ChatMessage parses voice attachment and forward preview', () {
  final message = ChatMessage.fromJson({
    'id': 'message-1',
    'conversation_id': 'conversation-1',
    'sender_id': 'user-1',
    'type': 'voice',
    'body': '',
    'attachment': {
      'bucket': 'voice-messages',
      'path': 'conversation-1/message-1.m4a',
      'mime_type': 'audio/mp4',
      'size': 1024,
      'duration_ms': 4200,
    },
    'forwarded_from': {
      'message_id': 'message-0',
      'sender_name': 'Ada',
      'type': 'text',
      'body': 'Original',
    },
    'created_at': '2026-05-18T00:00:00Z',
  });

  expect(message.voiceAttachment?.durationMs, 4200);
  expect(message.forwardPreview?.senderName, 'Ada');
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
rtk flutter test test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
```

Expected: failures for missing alias, voice attachment, forward preview, and daily-chat SQL contracts.

- [ ] **Step 4: Implement the migration**

Create `supabase/migrations/202605180010_daily_chat_polish_v3.sql` with:

```sql
create table if not exists public.contact_aliases (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  alias text not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (char_length(trim(alias)) between 1 and 48)
);

alter table public.contact_aliases enable row level security;

create policy contact_aliases_select_owner
  on public.contact_aliases for select
  to authenticated
  using (owner_id = auth.uid());

create or replace function public.set_contact_alias(
  target_friend_id uuid,
  new_alias text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_alias text := nullif(trim(new_alias), '');
begin
  if trimmed_alias is null then
    delete from public.contact_aliases
    where owner_id = auth.uid()
      and friend_id = target_friend_id;
    return;
  end if;

  if not exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(auth.uid(), target_friend_id)
      and f.user_high_id = greatest(auth.uid(), target_friend_id)
  ) then
    raise exception 'Aliases require friendship' using errcode = '42501';
  end if;

  insert into public.contact_aliases (owner_id, friend_id, alias)
  values (auth.uid(), target_friend_id, trimmed_alias)
  on conflict (owner_id, friend_id)
  do update set alias = excluded.alias, updated_at = now();
end;
$$;

create or replace function public.list_friends_with_aliases()
returns table (
  id uuid,
  username text,
  display_name text,
  alias text,
  avatar_url text,
  bio text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    ca.alias,
    p.avatar_url,
    p.bio,
    p.created_at,
    p.updated_at
  from public.friendships f
  join public.profiles p
    on p.id = case
      when f.user_low_id = auth.uid() then f.user_high_id
      else f.user_low_id
    end
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where auth.uid() in (f.user_low_id, f.user_high_id)
  order by coalesce(ca.alias, p.display_name), p.username;
$$;

alter table public.messages
  add column if not exists forwarded_from jsonb;

create index if not exists messages_body_search_idx
  on public.messages using gin (to_tsvector('simple', body));

create or replace function public.forward_message(
  source_message_id uuid,
  target_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  source_message public.messages%rowtype;
  created_message_id uuid;
begin
  select *
  into source_message
  from public.messages
  where id = source_message_id
    and recalled_at is null;

  if source_message.id is null
    or not public.is_current_user_conversation_member(source_message.conversation_id)
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Message cannot be forwarded' using errcode = '42501';
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment,
    forwarded_from
  )
  values (
    target_conversation_id,
    auth.uid(),
    source_message.type,
    source_message.body,
    source_message.attachment,
    jsonb_build_object(
      'message_id', source_message.id,
      'sender_id', source_message.sender_id,
      'type', source_message.type,
      'body', source_message.body
    )
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

create or replace function public.search_messages(
  search_query text
)
returns table (
  message_id uuid,
  conversation_id uuid,
  conversation_title text,
  sender_id uuid,
  sender_name text,
  body text,
  type text,
  created_at timestamptz,
  rank real
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id,
    m.conversation_id,
    coalesce(c.title, peer.display_name) as conversation_title,
    m.sender_id,
    sender.display_name as sender_name,
    m.body,
    m.type,
    m.created_at,
    ts_rank(
      to_tsvector('simple', m.body),
      websearch_to_tsquery('simple', trim(search_query))
    ) as rank
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  join public.profiles sender on sender.id = m.sender_id
  left join public.conversation_members direct_peer_membership
    on direct_peer_membership.conversation_id = c.id
    and direct_peer_membership.user_id <> auth.uid()
    and c.type = 'direct'
  left join public.profiles peer on peer.id = direct_peer_membership.user_id
  where trim(search_query) <> ''
    and m.recalled_at is null
    and public.is_current_user_conversation_member(m.conversation_id)
    and to_tsvector('simple', m.body)
      @@ websearch_to_tsquery('simple', trim(search_query))
  order by rank desc, m.created_at desc
  limit 50;
$$;

insert into storage.buckets (id, name, public)
values ('voice-messages', 'voice-messages', false)
on conflict (id) do update set public = false;

create policy voice_messages_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'voice-messages'
    and public.is_current_user_conversation_member(
      split_part(name, '/', 1)::uuid
    )
  );

create policy voice_messages_insert_member
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'voice-messages'
    and public.is_current_user_conversation_member(
      split_part(name, '/', 1)::uuid
    )
  );
```

- [ ] **Step 5: Extend the shared models**

In `lib/shared/models/profile.dart`, add:

```dart
final String? alias;

String get displayLabel {
  final value = alias?.trim();
  return value == null || value.isEmpty ? displayName : value;
}
```

In `lib/shared/models/message.dart`, add:

```dart
final ForwardPreview? forwardPreview;

VoiceAttachment? get voiceAttachment {
  final value = attachment;
  if (type != MessageType.voice || value == null) {
    return null;
  }
  return VoiceAttachment.fromJson(value);
}
```

and:

```dart
class ForwardPreview {
  const ForwardPreview({
    required this.messageId,
    required this.senderName,
    required this.type,
    required this.body,
  });
}

class VoiceAttachment {
  const VoiceAttachment({
    required this.bucket,
    required this.path,
    required this.mimeType,
    required this.size,
    required this.durationMs,
  });
}
```

- [ ] **Step 6: Verify and commit**

Run:

```bash
rtk dart format lib/shared/models/profile.dart lib/shared/models/message.dart test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
rtk flutter test test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
rtk flutter analyze
```

Expected: all targeted tests pass and analyzer reports no issues.

Commit:

```bash
rtk git add supabase/migrations/202605180010_daily_chat_polish_v3.sql lib/shared/models/profile.dart lib/shared/models/message.dart test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
rtk git commit -m "feat: add daily chat polish backend contracts"
```

## Task 2: Contact Aliases

**Files:**
- Modify: `lib/features/contacts/contacts_repository.dart`
- Create: `lib/features/contacts/contact_alias_sheet.dart`
- Modify: `lib/features/contacts/contacts_screen.dart`
- Modify: `test/features/contacts/contacts_screen_test.dart`

- [ ] **Step 1: Write failing repository and widget tests**

Add repository coverage:

```dart
test('setContactAlias calls the scoped RPC', () async {
  final dataSource = FakeContactsDataSource();
  final repository = SupabaseContactsRepository.withDataSource(dataSource);

  await repository.setContactAlias(friendId: 'user-2', alias: 'Ada L.');

  expect(dataSource.rpcCalls.single.functionName, 'set_contact_alias');
});
```

Add widget coverage:

```dart
testWidgets('friend tile shows alias and opens alias editor', (tester) async {
  await tester.pumpWidget(buildContactsScreen(friendAlias: 'Ada L.'));

  expect(find.text('Ada L.'), findsOneWidget);
  await tester.tap(find.byTooltip('Edit alias'));
  await tester.pumpAndSettle();
  expect(find.text('Edit alias'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
rtk flutter test test/features/contacts/contacts_screen_test.dart test/features/contacts/contacts_repository_test.dart
```

Expected: failures because alias APIs and sheet do not exist.

- [ ] **Step 3: Add repository APIs**

In `lib/features/contacts/contacts_repository.dart`, add:

```dart
Future<void> setContactAlias({
  required String friendId,
  required String? alias,
}) {
  return _dataSource.rpc('set_contact_alias', {
    'target_friend_id': friendId,
    'new_alias': alias,
  });
}
```

Update `listFriends()` to call `list_friends_with_aliases` and map the returned `alias` field into `Profile.alias`.

- [ ] **Step 4: Add the alias sheet**

Create `lib/features/contacts/contact_alias_sheet.dart` with:

```dart
class ContactAliasSheet extends ConsumerStatefulWidget {
  const ContactAliasSheet({required this.profile, super.key});

  final Profile profile;
}
```

The sheet should:
- initialize the text field from `profile.alias ?? ''`
- save trimmed text through `setContactAlias`
- treat an empty string as alias removal
- close only after a successful save
- render repository errors beneath the field

- [ ] **Step 5: Wire aliases into the contacts screen**

In `lib/features/contacts/contacts_screen.dart`:

```dart
title: Text(profile.displayLabel),
subtitle: Text('@${profile.username}'),
trailing: Wrap(
  children: [
    IconButton(
      tooltip: 'Edit alias',
      icon: const Icon(Icons.edit_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => ContactAliasSheet(profile: profile),
      ),
    ),
    _MessageFriendButton(profile: profile),
  ],
),
```

- [ ] **Step 6: Verify and commit**

Run:

```bash
rtk dart format lib/features/contacts test/features/contacts
rtk flutter test test/features/contacts
rtk flutter analyze
```

Commit:

```bash
rtk git add lib/features/contacts test/features/contacts
rtk git commit -m "feat: add contact aliases"
```

## Task 3: Voice Message Transport

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `ios/Runner/Info.plist`
- Modify: `macos/Runner/Info.plist`
- Modify: `macos/Runner/DebugProfile.entitlements`
- Modify: `macos/Runner/Release.entitlements`
- Modify: `lib/features/chats/chats_repository.dart`
- Modify: `test/features/chats/chats_repository_test.dart`

- [ ] **Step 1: Add package dependencies**

Run:

```bash
rtk flutter pub add record just_audio
```

Expected: `pubspec.yaml` and `pubspec.lock` gain `record` and `just_audio`.

- [ ] **Step 2: Write failing repository test**

Add to `test/features/chats/chats_repository_test.dart`:

```dart
test('sendVoiceMessage uploads audio and inserts a voice message', () async {
  final dataSource = FakeChatsDataSource();
  final repository = SupabaseChatsRepository.withDataSource(
    dataSource,
    currentUserId: () => 'user-1',
  );

  await repository.sendVoiceMessage(
    conversationId: 'conversation-1',
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'audio/mp4',
    durationMs: 4200,
  );

  expect(dataSource.uploads.single.bucket, 'voice-messages');
  expect(dataSource.insertedMessages.single['type'], 'voice');
  expect(
    dataSource.insertedMessages.single['attachment']['duration_ms'],
    4200,
  );
});
```

- [ ] **Step 3: Run the test and verify failure**

Run:

```bash
rtk flutter test test/features/chats/chats_repository_test.dart
```

Expected: failure because `sendVoiceMessage` is missing.

- [ ] **Step 4: Implement repository support**

In `lib/features/chats/chats_repository.dart`, add:

```dart
Future<void> sendVoiceMessage({
  required String conversationId,
  required Uint8List bytes,
  required String mimeType,
  required int durationMs,
}) async {
  final messageId = const Uuid().v4();
  final path = '$conversationId/$messageId.m4a';

  await _dataSource.uploadBinary(
    bucket: 'voice-messages',
    path: path,
    bytes: bytes,
    mimeType: mimeType,
  );

  await _dataSource.insertMessage({
    'id': messageId,
    'conversation_id': conversationId,
    'sender_id': _requireCurrentUserId(),
    'type': MessageType.voice.toJson(),
    'body': '',
    'attachment': {
      'bucket': 'voice-messages',
      'path': path,
      'mime_type': mimeType,
      'size': bytes.length,
      'duration_ms': durationMs,
    },
  });
}
```

- [ ] **Step 5: Add microphone permissions**

Add to both `ios/Runner/Info.plist` and `macos/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>WeCord uses the microphone to record voice messages.</string>
```

Add to both macOS entitlements files:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

- [ ] **Step 6: Verify and commit**

Run:

```bash
rtk flutter test test/features/chats/chats_repository_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add pubspec.yaml pubspec.lock ios/Runner/Info.plist macos/Runner/Info.plist macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements lib/features/chats/chats_repository.dart test/features/chats/chats_repository_test.dart
rtk git commit -m "feat: add voice message transport"
```

## Task 4: Voice Recording And Playback UI

**Files:**
- Create: `lib/features/chats/voice_message_recorder.dart`
- Create: `lib/features/chats/voice_message_player.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `lib/features/chats/chats_screen.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`
- Modify: `test/features/chats/chats_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add:

```dart
testWidgets('composer can record and send a voice message', (tester) async {
  await tester.pumpWidget(buildThread());

  await tester.tap(find.byTooltip('Record voice message'));
  await tester.pump();
  expect(find.text('Recording...'), findsOneWidget);

  await tester.tap(find.byTooltip('Send voice message'));
  await tester.pumpAndSettle();
  expect(fakeRepository.sentVoiceMessages, hasLength(1));
});

testWidgets('voice messages render a playback control', (tester) async {
  await tester.pumpWidget(buildThread(messages: [voiceMessage]));

  expect(find.byTooltip('Play voice message'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
rtk flutter test test/features/chats/chat_thread_screen_test.dart test/features/chats/chats_screen_test.dart
```

Expected: failures because voice controls and previews are missing.

- [ ] **Step 3: Create recorder boundary**

Create `lib/features/chats/voice_message_recorder.dart` with:

```dart
class RecordedVoiceMessage {
  const RecordedVoiceMessage({
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
  });
}

abstract interface class VoiceMessageRecorder {
  Future<void> start();
  Future<RecordedVoiceMessage?> stop();
  Future<void> cancel();
}
```

Provide a production implementation backed by `AudioRecorder` and a fake implementation for widget tests.

- [ ] **Step 4: Create playback widget**

Create `lib/features/chats/voice_message_player.dart` with:

```dart
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({required this.attachment, super.key});

  final VoiceAttachment attachment;
}
```

The widget should show:
- play / pause button
- formatted duration
- disabled/error state if signed URL generation or playback fails

- [ ] **Step 5: Wire the thread and chat list**

In `chat_thread_screen.dart`:
- add record / cancel / send controls when the composer is idle
- render `VoiceMessagePlayer` for `MessageType.voice`
- keep text/image send controls unchanged

In `chats_screen.dart`, preview voice messages as:

```dart
final lastMessage = conversation.lastMessageType == MessageType.voice
    ? '[Voice]'
    : conversation.lastMessageBody?.trim().isNotEmpty == true
        ? conversation.lastMessageBody!
        : 'No messages yet';
```

- [ ] **Step 6: Verify and commit**

Run:

```bash
rtk dart format lib/features/chats test/features/chats
rtk flutter test test/features/chats/chat_thread_screen_test.dart test/features/chats/chats_screen_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add lib/features/chats test/features/chats
rtk git commit -m "feat: add voice message UI"
```

## Task 5: Message Forwarding

**Files:**
- Modify: `lib/features/chats/chats_repository.dart`
- Create: `lib/features/chats/message_forward_sheet.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `test/features/chats/chats_repository_test.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`

- [ ] **Step 1: Write failing repository and widget tests**

Add repository test:

```dart
test('forwardMessage calls the forwarding RPC', () async {
  final dataSource = FakeChatsDataSource();
  final repository = SupabaseChatsRepository.withDataSource(
    dataSource,
    currentUserId: () => 'user-1',
  );

  await repository.forwardMessage(
    sourceMessageId: 'message-1',
    targetConversationId: 'conversation-2',
  );

  expect(dataSource.rpcCalls.single.functionName, 'forward_message');
});
```

Add widget test:

```dart
testWidgets('message action menu can open the forward sheet', (tester) async {
  await tester.pumpWidget(buildThread(messages: [textMessage]));

  await tester.longPress(find.text('hello'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Forward'));
  await tester.pumpAndSettle();

  expect(find.text('Forward to'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
rtk flutter test test/features/chats/chats_repository_test.dart test/features/chats/chat_thread_screen_test.dart
```

Expected: failures because forward APIs and UI are missing.

- [ ] **Step 3: Add repository support**

In `lib/features/chats/chats_repository.dart`, add:

```dart
Future<void> forwardMessage({
  required String sourceMessageId,
  required String targetConversationId,
}) {
  return _dataSource.rpc('forward_message', {
    'source_message_id': sourceMessageId,
    'target_conversation_id': targetConversationId,
  });
}
```

- [ ] **Step 4: Build the forward sheet**

Create `lib/features/chats/message_forward_sheet.dart` with:

```dart
class MessageForwardSheet extends ConsumerWidget {
  const MessageForwardSheet({required this.message, super.key});

  final ChatMessage message;
}
```

The sheet should:
- list visible conversations from `conversationsProvider`
- allow search by title
- forward into exactly one target in the MVP
- close after success and show a `SnackBar('Message forwarded')`

- [ ] **Step 5: Add the thread action**

In `chat_thread_screen.dart`, add a `Forward` option next to Copy / Reply / Edit / Recall for non-recalled messages and open `MessageForwardSheet`.

- [ ] **Step 6: Verify and commit**

Run:

```bash
rtk dart format lib/features/chats test/features/chats
rtk flutter test test/features/chats/chats_repository_test.dart test/features/chats/chat_thread_screen_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add lib/features/chats test/features/chats
rtk git commit -m "feat: add message forwarding"
```

## Task 6: Global Message Search

**Files:**
- Modify: `lib/features/chats/chats_repository.dart`
- Create: `lib/features/chats/global_message_search_screen.dart`
- Modify: `lib/features/chats/chats_screen.dart`
- Modify: `lib/shared/navigation/app_router.dart`
- Modify: `test/features/chats/chats_repository_test.dart`
- Create: `test/features/chats/global_message_search_screen_test.dart`
- Modify: `test/shared/navigation/app_router_test.dart`

- [ ] **Step 1: Write failing tests**

Add repository test:

```dart
test('searchMessages maps global search rows', () async {
  final dataSource = FakeChatsDataSource()
    ..searchRows = [
      {
        'message_id': 'message-1',
        'conversation_id': 'conversation-1',
        'conversation_title': 'Launch Crew',
        'sender_id': 'user-2',
        'sender_name': 'Ada',
        'body': 'ship it',
        'type': 'text',
        'created_at': '2026-05-18T00:00:00Z',
        'rank': 0.9,
      },
    ];

  final repository = SupabaseChatsRepository.withDataSource(
    dataSource,
    currentUserId: () => 'user-1',
  );

  final results = await repository.searchMessages('ship');
  expect(results.single.body, 'ship it');
  expect(results.single.conversationTitle, 'Launch Crew');
});
```

Add screen test:

```dart
testWidgets('global search opens a matching conversation', (tester) async {
  await tester.pumpWidget(buildGlobalSearchScreen());

  await tester.enterText(find.byType(TextField), 'ship');
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('ship it'));

  expect(fakeRouter.lastLocation, '/chats/conversation-1');
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
rtk flutter test test/features/chats/chats_repository_test.dart test/features/chats/global_message_search_screen_test.dart test/shared/navigation/app_router_test.dart
```

Expected: failures because global search types and routes are missing.

- [ ] **Step 3: Add repository types**

In `lib/features/chats/chats_repository.dart`, add:

```dart
class MessageSearchResult {
  const MessageSearchResult({
    required this.messageId,
    required this.conversationId,
    required this.conversationTitle,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.rank,
  });
}

Future<List<MessageSearchResult>> searchMessages(String query) async {
  final rows = await _dataSource.rpc('search_messages', {
    'search_query': query.trim(),
  }) as List<dynamic>;
  return rows
      .cast<Map<String, dynamic>>()
      .map(MessageSearchResult.fromJson)
      .toList(growable: false);
}
```

- [ ] **Step 4: Add route and screen**

Create `lib/features/chats/global_message_search_screen.dart` with:

```dart
class GlobalMessageSearchScreen extends ConsumerStatefulWidget {
  const GlobalMessageSearchScreen({super.key});

  static const path = '/search/messages';
}
```

Behavior:
- debounce non-empty queries by 250 ms
- show empty, loading, result, and error states
- result rows show `conversationTitle`, `senderName`, body snippet, and timestamp
- tap navigates to the matching thread

Add a route in `app_router.dart` and add a search icon in `chats_screen.dart` that opens the route.

- [ ] **Step 5: Verify and commit**

Run:

```bash
rtk dart format lib/features/chats lib/shared/navigation test/features/chats test/shared/navigation
rtk flutter test test/features/chats/chats_repository_test.dart test/features/chats/global_message_search_screen_test.dart test/shared/navigation/app_router_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add lib/features/chats lib/shared/navigation test/features/chats test/shared/navigation
rtk git commit -m "feat: add global message search"
```

## Task 7: End-To-End Integration And Docs

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-05-18-wecord-design.md`
- Modify: affected tests if fixtures need new fields.

- [ ] **Step 1: Update product docs**

In `README.md`, extend `Current Status` with:

```markdown
contact aliases, voice messages, message forwarding, and global message search
```

In `docs/superpowers/specs/2026-05-18-wecord-design.md`, add a short milestone note documenting that v3 completes the “daily chat polish” layer before moments / circles work begins.

- [ ] **Step 2: Run full verification**

Run:

```bash
rtk flutter analyze
rtk flutter test
rtk supabase db push
```

Expected:
- analyzer reports no issues
- full test suite passes
- migration `202605180010_daily_chat_polish_v3.sql` applies successfully

- [ ] **Step 3: Manual smoke test**

Run:

```bash
rtk flutter run -d chrome --dart-define-from-file=.env
rtk flutter run -d macos --dart-define-from-file=.env
```

Verify:
- alias edits persist and appear in contacts and chat surfaces
- voice recording works on web and macOS, and playback works after reload
- forwarding preserves text/image/voice type and creates a new message
- global search returns only visible messages and opens the right thread

- [ ] **Step 4: Commit**

```bash
rtk git add README.md docs/superpowers/specs/2026-05-18-wecord-design.md
rtk git commit -m "docs: update daily chat polish milestone"
```

## Self-Review

- **Spec coverage:** The plan covers the four chosen daily-driver features: aliases, voice messages, forwarding, and global search.
- **Scope check:** Moments and channels remain separate later milestones because they introduce independent social and server-like subsystems.
- **Placeholder scan:** No `TBD`, `TODO`, or vague implementation placeholders remain.
- **Type consistency:** `VoiceAttachment`, `ForwardPreview`, `MessageSearchResult`, and alias APIs keep the same names across tasks.
