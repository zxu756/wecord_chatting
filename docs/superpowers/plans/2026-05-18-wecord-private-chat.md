# WeCord Private Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable WeCord chat slice: email auth, profile creation, friend requests, direct conversations, text messages, unread state, and basic realtime refresh.

**Architecture:** Supabase remains the source of truth. The client keeps Supabase access behind feature repositories, exposes state through Riverpod providers, and renders focused feature screens that can be widget-tested with fake repositories. Private chats, future groups, and future channels all use the same `conversations` and `messages` shape.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, Supabase Auth/Postgres/Realtime, SQL migrations, flutter_test.

---

## Scope

This plan implements Milestone 2 from the approved WeCord MVP spec.

Included:

- Supabase SQL schema for profiles, friendships, friend requests, conversations, conversation members, messages, and blocks.
- RLS policies for private chat membership and friend workflows.
- Email/password auth screens and auth state routing.
- Profile bootstrap after sign-up.
- Contact search by username.
- Friend request create, accept, reject.
- Friend list.
- Direct conversation creation.
- Chat list with last message and unread count.
- Text message send/receive.
- Basic realtime invalidation for conversation lists and active messages.

Deferred to later plans:

- Group chat.
- Circles and channels.
- Media uploads.
- Message reply/edit/recall.
- Typing indicators.
- Presence.
- Push notifications.
- AI features.

## File Structure

- Create: `supabase/migrations/202605180001_private_chat.sql` for schema, indexes, functions, triggers, and RLS.
- Create: `test/supabase/private_chat_schema_test.dart` for SQL smoke checks.
- Create: `lib/shared/api/supabase_providers.dart` for typed Supabase client providers.
- Create: `lib/shared/models/profile.dart`.
- Create: `lib/shared/models/friend_request.dart`.
- Create: `lib/shared/models/friendship.dart`.
- Create: `lib/shared/models/conversation.dart`.
- Create: `lib/shared/models/message.dart`.
- Create: `lib/features/auth/auth_repository.dart`.
- Create: `lib/features/auth/auth_controller.dart`.
- Create: `lib/features/auth/auth_screen.dart`.
- Create: `test/features/auth/auth_controller_test.dart`.
- Create: `test/features/auth/auth_screen_test.dart`.
- Create: `lib/features/contacts/contacts_repository.dart`.
- Modify: `lib/features/contacts/contacts_screen.dart`.
- Create: `test/features/contacts/contacts_repository_test.dart`.
- Create: `test/features/contacts/contacts_screen_test.dart`.
- Create: `lib/features/chats/chats_repository.dart`.
- Modify: `lib/features/chats/chats_screen.dart`.
- Create: `lib/features/chats/chat_thread_screen.dart`.
- Modify: `lib/shared/navigation/app_router.dart`.
- Create: `test/features/chats/chats_repository_test.dart`.
- Create: `test/features/chats/chats_screen_test.dart`.
- Create: `test/features/chats/chat_thread_screen_test.dart`.
- Modify: `README.md` with Supabase migration notes.

## Task 1: Supabase Private Chat Schema

**Files:**
- Create: `supabase/migrations/202605180001_private_chat.sql`
- Create: `test/supabase/private_chat_schema_test.dart`

- [ ] **Step 1: Write SQL smoke tests**

Create `test/supabase/private_chat_schema_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202605180001_private_chat.sql',
  );

  test('private chat migration declares required tables', () {
    final sql = migration.readAsStringSync();

    for (final table in [
      'profiles',
      'friend_requests',
      'friendships',
      'conversations',
      'conversation_members',
      'messages',
      'blocks',
    ]) {
      expect(sql, contains('create table public.$table'));
      expect(sql, contains('alter table public.$table enable row level security'));
    }
  });

  test('private chat migration declares direct conversation RPCs', () {
    final sql = migration.readAsStringSync();

    expect(sql, contains('create or replace function public.accept_friend_request'));
    expect(sql, contains('create or replace function public.get_or_create_direct_conversation'));
    expect(sql, contains('create or replace function public.touch_conversation_from_message'));
  });

  test('private chat migration protects message access by membership', () {
    final sql = migration.readAsStringSync();

    expect(sql, contains('messages_select_member'));
    expect(sql, contains('messages_insert_member'));
    expect(sql, contains('conversation_members'));
    expect(sql, contains('auth.uid()'));
  });
}
```

- [ ] **Step 2: Run schema tests to verify red**

Run:

```bash
rtk flutter test test/supabase/private_chat_schema_test.dart
```

Expected: fail because `supabase/migrations/202605180001_private_chat.sql` does not exist.

- [ ] **Step 3: Create migration**

Create `supabase/migrations/202605180001_private_chat.sql` with these sections:

```sql
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null,
  avatar_url text,
  bio text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_length check (char_length(username) between 3 and 24),
  constraint username_format check (username ~ '^[a-z0-9_]+$')
);

create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_requests_not_self check (requester_id <> receiver_id),
  constraint friend_requests_unique_pair unique (requester_id, receiver_id)
);

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_low_id uuid not null references public.profiles(id) on delete cascade,
  user_high_id uuid not null references public.profiles(id) on delete cascade,
  user_low_remark text,
  user_high_remark text,
  created_at timestamptz not null default now(),
  constraint friendships_ordered_pair check (user_low_id < user_high_id),
  constraint friendships_unique_pair unique (user_low_id, user_high_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('direct', 'group', 'channel')),
  title text,
  avatar_url text,
  last_message_id uuid,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  pinned_at timestamptz,
  muted_until timestamptz,
  last_read_message_id uuid,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  type text not null default 'text' check (type in ('text', 'image', 'file', 'voice')),
  body text not null default '',
  attachment jsonb,
  reply_to_message_id uuid references public.messages(id) on delete set null,
  edited_at timestamptz,
  recalled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint message_body_not_empty check (type <> 'text' or char_length(trim(body)) > 0)
);

alter table public.conversations
  add constraint conversations_last_message_fk
  foreign key (last_message_id) references public.messages(id) on delete set null;

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);
```

Add indexes, updated-at trigger, `accept_friend_request(request_id uuid)`, `get_or_create_direct_conversation(other_user_id uuid)`, `touch_conversation_from_message()`, row-level security, and policies. Use membership checks for conversations/messages and own-user checks for profiles, friend requests, friendships, and blocks.

- [ ] **Step 4: Run schema tests**

Run:

```bash
rtk flutter test test/supabase/private_chat_schema_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
rtk git add supabase/migrations/202605180001_private_chat.sql test/supabase/private_chat_schema_test.dart
rtk git commit -m "feat: add private chat database schema"
```

Expected: commit succeeds.

## Task 2: Shared Private Chat Models

**Files:**
- Create: `lib/shared/models/profile.dart`
- Create: `lib/shared/models/friend_request.dart`
- Create: `lib/shared/models/friendship.dart`
- Create: `lib/shared/models/conversation.dart`
- Create: `lib/shared/models/message.dart`
- Create: `test/shared/models/private_chat_models_test.dart`

- [ ] **Step 1: Write model tests**

Create `test/shared/models/private_chat_models_test.dart` that verifies `fromJson` and `copyWith` for all five model classes. Use fixed ISO timestamps and maps matching the Supabase column names:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/friendship.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  test('Profile parses Supabase rows', () {
    final profile = Profile.fromJson({
      'id': 'user-1',
      'username': 'alex',
      'display_name': 'Alex',
      'avatar_url': null,
      'bio': 'hello',
      'created_at': '2026-05-18T00:00:00.000Z',
      'updated_at': '2026-05-18T00:01:00.000Z',
    });

    expect(profile.id, 'user-1');
    expect(profile.username, 'alex');
    expect(profile.displayName, 'Alex');
    expect(profile.bio, 'hello');
    expect(profile.copyWith(displayName: 'A').displayName, 'A');
  });

  test('Conversation computes unread count from row value', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'direct',
      'title': null,
      'avatar_url': null,
      'last_message_body': 'Hi',
      'last_message_at': '2026-05-18T00:00:00.000Z',
      'unread_count': 2,
    });

    expect(conversation.id, 'conversation-1');
    expect(conversation.type, ConversationType.direct);
    expect(conversation.lastMessageBody, 'Hi');
    expect(conversation.unreadCount, 2);
  });

  test('Message parses text rows', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'text',
      'body': 'Hello',
      'created_at': '2026-05-18T00:00:00.000Z',
      'edited_at': null,
      'recalled_at': null,
    });

    expect(message.type, MessageType.text);
    expect(message.body, 'Hello');
    expect(message.copyWith(body: 'Updated').body, 'Updated');
  });
}
```

- [ ] **Step 2: Run model tests to verify red**

Run:

```bash
rtk flutter test test/shared/models/private_chat_models_test.dart
```

Expected: fail because model files do not exist.

- [ ] **Step 3: Implement models**

Implement immutable Dart classes with:

- Required final fields.
- `factory fromJson(Map<String, dynamic> json)`.
- `Map<String, dynamic> toJson()` where useful for inserts.
- `copyWith`.
- Enum parsers for `ConversationType`, `MessageType`, and friend request status.

Use `DateTime.parse(value as String).toUtc()` for timestamps. Keep parsing helpers private inside each model file.

- [ ] **Step 4: Run model tests and full tests**

Run:

```bash
rtk flutter test test/shared/models/private_chat_models_test.dart
rtk flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
rtk git add lib/shared/models test/shared/models/private_chat_models_test.dart
rtk git commit -m "feat: add private chat models"
```

Expected: commit succeeds.

## Task 3: Auth Repository, Controller, and Screen

**Files:**
- Create: `lib/shared/api/supabase_providers.dart`
- Create: `lib/features/auth/auth_repository.dart`
- Create: `lib/features/auth/auth_controller.dart`
- Create: `lib/features/auth/auth_screen.dart`
- Modify: `lib/shared/navigation/app_router.dart`
- Modify: `lib/bootstrap/app_bootstrap.dart`
- Create: `test/features/auth/auth_controller_test.dart`
- Create: `test/features/auth/auth_screen_test.dart`

- [ ] **Step 1: Write auth controller tests**

Create tests with a fake repository that records calls:

- `signIn` trims email and delegates password unchanged.
- `signUp` requires username, display name, email, and password.
- Controller exposes loading and error states.

Expected failure before implementation: missing `AuthController` and `AuthRepository`.

- [ ] **Step 2: Implement Supabase providers and auth repository**

Create `supabaseClientProvider` that returns `Supabase.instance.client`.

Create `AuthRepository` interface and `SupabaseAuthRepository` implementation:

- `Stream<AuthUser?> authStateChanges()`
- `AuthUser? currentUser()`
- `Future<void> signIn({required String email, required String password})`
- `Future<void> signUp({required String email, required String password, required String username, required String displayName})`
- `Future<void> signOut()`

After sign-up, upsert `profiles` with the new user id, lowercase username, display name, and empty bio.

- [ ] **Step 3: Implement auth controller**

Use `StateNotifier<AuthFormState>` for form actions and a separate provider for current auth user stream. Keep state small:

- `isLoading`
- `errorMessage`

- [ ] **Step 4: Implement auth screen**

Create an email/password auth screen with:

- Toggle between Sign in and Create account.
- Username/display name fields only in create-account mode.
- Email/password fields.
- Primary submit button.
- Error text.

- [ ] **Step 5: Gate router by auth state**

Update router to show `/auth` when signed out and shell routes when signed in. In tests, allow overriding auth providers so existing router tests can simulate a signed-in user without Supabase.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
rtk flutter test test/features/auth/auth_controller_test.dart test/features/auth/auth_screen_test.dart
rtk flutter test
rtk flutter analyze
rtk git add lib/shared/api lib/features/auth lib/shared/navigation/app_router.dart lib/bootstrap/app_bootstrap.dart test/features/auth test/shared/navigation/app_router_test.dart
rtk git commit -m "feat: add email auth flow"
```

Expected: all tests and analyzer pass.

## Task 4: Contacts and Friend Requests

**Files:**
- Create: `lib/features/contacts/contacts_repository.dart`
- Modify: `lib/features/contacts/contacts_screen.dart`
- Create: `test/features/contacts/contacts_repository_test.dart`
- Create: `test/features/contacts/contacts_screen_test.dart`

- [ ] **Step 1: Write contacts repository tests**

Use a fake Supabase-style data source or fake repository implementation to verify:

- Search ignores the current user.
- Send request inserts a pending request.
- Accept request calls `accept_friend_request`.
- Reject request updates status to `rejected`.

- [ ] **Step 2: Implement contacts repository**

Create `ContactsRepository` interface and `SupabaseContactsRepository` implementation:

- `Future<List<Profile>> searchProfiles(String query)`
- `Future<List<Profile>> listFriends()`
- `Future<List<FriendRequest>> listIncomingRequests()`
- `Future<void> sendFriendRequest(String receiverId)`
- `Future<void> acceptFriendRequest(String requestId)`
- `Future<void> rejectFriendRequest(String requestId)`

- [ ] **Step 3: Implement contacts screen**

Screen sections:

- Search field.
- Search results with Add button.
- Incoming requests with Accept/Reject buttons.
- Friends list.

Use Riverpod providers for async sections and refresh after mutations.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
rtk flutter test test/features/contacts
rtk flutter test
rtk flutter analyze
rtk git add lib/features/contacts test/features/contacts
rtk git commit -m "feat: add friends and contact requests"
```

Expected: all tests and analyzer pass.

## Task 5: Direct Conversations and Chat List

**Files:**
- Create: `lib/features/chats/chats_repository.dart`
- Modify: `lib/features/chats/chats_screen.dart`
- Modify: `lib/shared/navigation/app_router.dart`
- Create: `test/features/chats/chats_repository_test.dart`
- Create: `test/features/chats/chats_screen_test.dart`

- [ ] **Step 1: Write chat repository tests**

Verify:

- Conversation list maps rows to `ConversationSummary`.
- `getOrCreateDirectConversation` calls the Supabase RPC.
- Unread count is preserved from query results.

- [ ] **Step 2: Implement chats repository**

Create `ChatsRepository` interface and `SupabaseChatsRepository`:

- `Future<List<ConversationSummary>> listConversations()`
- `Future<String> getOrCreateDirectConversation(String otherUserId)`
- `Stream<void> conversationChanges()`

For list queries, use a Postgres view or RPC if added to migration. If the view is not present, add it to the migration and update schema tests.

- [ ] **Step 3: Implement chat list UI**

Replace the empty Chats screen with:

- Loading state.
- Empty state.
- Conversation rows with title, last message, time, unread badge.
- Tap row navigates to `/chats/:conversationId`.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
rtk flutter test test/features/chats/chats_repository_test.dart test/features/chats/chats_screen_test.dart
rtk flutter test
rtk flutter analyze
rtk git add lib/features/chats lib/shared/navigation/app_router.dart test/features/chats supabase/migrations/202605180001_private_chat.sql test/supabase/private_chat_schema_test.dart
rtk git commit -m "feat: add direct conversation list"
```

Expected: all tests and analyzer pass.

## Task 6: Chat Thread and Text Messages

**Files:**
- Modify: `lib/features/chats/chats_repository.dart`
- Create: `lib/features/chats/chat_thread_screen.dart`
- Modify: `lib/shared/navigation/app_router.dart`
- Create: `test/features/chats/chat_thread_screen_test.dart`

- [ ] **Step 1: Write thread screen tests**

Verify:

- Existing messages render in chronological order.
- Empty composer button does not send.
- Non-empty composer sends trimmed text.
- Failed send shows retryable error text.

- [ ] **Step 2: Extend chats repository**

Add:

- `Future<List<ChatMessage>> listMessages(String conversationId)`
- `Future<void> sendTextMessage({required String conversationId, required String body})`
- `Future<void> markConversationRead(String conversationId)`
- `Stream<void> messageChanges(String conversationId)`

Use optimistic UI state in the screen, but rely on server ids for persisted messages.

- [ ] **Step 3: Implement chat thread screen**

Thread layout:

- App bar with conversation title.
- Scrollable message list.
- Right-aligned bubbles for current user.
- Left-aligned bubbles for other users.
- Text composer with send button.
- Loading and error states.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
rtk flutter test test/features/chats/chat_thread_screen_test.dart
rtk flutter test
rtk flutter analyze
rtk git add lib/features/chats lib/shared/navigation/app_router.dart test/features/chats
rtk git commit -m "feat: add text message thread"
```

Expected: all tests and analyzer pass.

## Task 7: Private Chat Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README**

Add a Private Chat status section:

```markdown
## Private Chat Milestone

This milestone adds email auth, profiles, friends, direct conversations, text messages, unread state, and basic realtime refresh.

Apply the Supabase migration before running against a real project:

```bash
supabase db push
```
```

- [ ] **Step 2: Run full verification**

Run:

```bash
rtk flutter analyze
rtk flutter test
rtk rg -n "T[O]DO|T[B]D|F[I]XME" README.md docs/superpowers/plans/2026-05-18-wecord-private-chat.md lib test supabase
rtk git status --short --branch
```

Expected:

- Analyzer has no issues.
- All tests pass.
- Marker scan has no output.
- Git status is clean after final commit.

- [ ] **Step 3: Commit README if changed**

Run:

```bash
rtk git add README.md
rtk git commit -m "docs: document private chat milestone"
```

Expected: commit succeeds if README changed.

## Self-Review

Spec coverage:

- Account: email/password auth and profile bootstrap are covered in Task 3.
- Friends: search, request, accept, reject, and list are covered in Task 4.
- Conversations: direct conversations, chat list, last message, and unread count are covered in Task 5.
- Messaging: text message list and send are covered in Task 6.
- Realtime: basic repository streams are covered in Tasks 5 and 6.
- RLS: membership checks and own-user checks are covered in Task 1.

Deferred requirements are intentional and assigned to later milestones: group chat, circles/channels, media, reply/edit/recall, typing, presence, push notifications, and search.

Placeholder scan:

- This plan uses no unfinished-work markers.
- Each task has concrete files, commands, and expected outcomes.

Type consistency:

- `Profile`, `FriendRequest`, `Friendship`, `ConversationSummary`, and `ChatMessage` are introduced before repositories use them.
- Repository method names are consistent across tests, providers, and screens.
- Route names stay under `/chats`, `/contacts`, `/circles`, `/me`, and `/auth`.
