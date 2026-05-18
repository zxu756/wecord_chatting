# Community & Discovery v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable WeCord community layer: Circles with channels and feed posts, stronger group announcements, grouped discovery, and chat media browsing.

**Architecture:** Add a Supabase-backed Circle domain that reuses existing `conversations`, `conversation_members`, and `messages` for Circle channels. Keep widgets thin by routing all database/storage work through repositories, following the existing chats/contacts/settings patterns. Implement the milestone in slices that can be tested independently: backend schema, Circle list/detail, Circle feed, group announcements, discovery, media center, then integration.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase Postgres/RLS/RPC/Storage, `flutter_test`, existing WeCord repository/data-source patterns.

---

## File Structure

- Create `supabase/migrations/202605190003_community_discovery_v1.sql`: Circle tables, RLS, RPCs, group announcement extension, media/discovery RPCs.
- Modify `test/supabase/private_chat_schema_test.dart`: schema assertions for Circle tables, RPCs, permissions, media/discovery, and announcement contracts.
- Create `lib/shared/models/circle.dart`: `CircleSummary`, `CircleDetail`, `CircleMember`, `CircleChannel`, `CirclePost`, `CirclePostComment`.
- Create `lib/shared/models/discovery.dart`: grouped discovery result model.
- Create `lib/shared/models/media_attachment.dart`: conversation media row model.
- Modify `lib/shared/models/conversation.dart`: ensure channel summaries and announcements keep mapping correctly.
- Modify `lib/shared/models/group.dart`: add announcement metadata if not already sufficient.
- Replace `lib/features/circles/circles_repository.dart`: Supabase repository and fake-friendly interface.
- Replace `lib/features/circles/circles_screen.dart`: Circle list, empty state, and creation entry.
- Create `lib/features/circles/circle_creation_sheet.dart`: create Circle form and friend picker.
- Create `lib/features/circles/circle_detail_screen.dart`: Circle detail with Channels and Feed tabs.
- Create `lib/features/circles/circle_channel_creation_sheet.dart`: create channel form.
- Create `lib/features/circles/circle_invite_sheet.dart`: invite friends to Circle.
- Create `lib/features/circles/circle_feed_composer.dart`: text/image post composer.
- Create `lib/features/circles/circle_post_tile.dart`: feed post, like/comment/delete/report actions.
- Modify `lib/features/groups/group_detail_sheet.dart`: announcement display/edit affordance cleanup.
- Modify `lib/features/chats/chat_thread_screen.dart`: announcement strip and media-center action.
- Create `lib/features/chats/chat_media_screen.dart`: media list and preview/playback surface.
- Modify `lib/features/chats/chats_repository.dart`: discovery/media methods and group announcement mapping.
- Rename or replace `lib/features/chats/global_message_search_screen.dart` with grouped discovery behavior while preserving `GlobalMessageSearchScreen.path`.
- Modify `lib/shared/navigation/app_router.dart`: Circle detail routes and chat media route.
- Add tests under `test/features/circles/`, `test/features/chats/`, `test/features/groups/`, `test/shared/models/`, and update existing navigation/search tests.

## Task 1: Backend Schema And Contract Tests

**Files:**
- Create: `supabase/migrations/202605190003_community_discovery_v1.sql`
- Modify: `test/supabase/private_chat_schema_test.dart`

- [ ] **Step 1: Write failing schema tests**

Add tests to `test/supabase/private_chat_schema_test.dart`:

```dart
test('community discovery v1 declares circle tables and policies', () {
  final sql = effectiveMigrationSql();
  for (final table in [
    'circles',
    'circle_members',
    'circle_channels',
    'circle_posts',
    'circle_post_likes',
    'circle_post_comments',
  ]) {
    expect(sql, contains('create table if not exists public.$table'));
    expect(sql, contains('alter table public.$table enable row level security'));
  }
  expect(sql, contains('circle_members_role_check'));
  expect(sql, contains("role in ('owner', 'admin', 'member')"));
  expect(sql, contains('circle_channels_conversation_unique'));
});

test('community discovery v1 exposes narrow circle RPCs', () {
  final sql = effectiveMigrationSql();
  for (final functionName in [
    'create_circle',
    'list_circle_summaries',
    'get_circle_detail',
    'create_circle_channel',
    'invite_circle_members',
    'create_circle_post',
    'toggle_circle_post_like',
    'create_circle_post_comment',
    'delete_circle_post',
    'report_circle_post',
  ]) {
    expect(
      sql,
      contains('create or replace function public.$functionName'),
      reason: 'Missing $functionName',
    );
  }
  expect(functionBody(sql, 'create_circle'), contains("values ('channel'"));
  expect(functionBody(sql, 'create_circle'), contains("'general'"));
  expect(functionBody(sql, 'invite_circle_members'), contains('friendships'));
  expect(functionBody(sql, 'invite_circle_members'), contains('are_users_blocked'));
});

test('community discovery v1 extends group announcements and discovery', () {
  final sql = effectiveMigrationSql();
  expect(sql, contains('add column if not exists announcement_updated_at'));
  expect(sql, contains('add column if not exists announcement_updated_by'));
  expect(functionBody(sql, 'update_group_profile'), contains('announcement_updated_at'));
  expect(functionBody(sql, 'search_discovery'), contains('circle_channels'));
  expect(functionBody(sql, 'list_conversation_media'), contains("m.type in ('image', 'voice', 'file')"));
});
```

- [ ] **Step 2: Run schema tests and verify they fail**

Run:

```bash
rtk flutter test test/supabase/private_chat_schema_test.dart
```

Expected: FAIL because `202605190003_community_discovery_v1.sql` and the listed functions/tables do not exist yet.

- [ ] **Step 3: Add the migration**

Create `supabase/migrations/202605190003_community_discovery_v1.sql` with these contracts:

```sql
create table if not exists public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  avatar_url text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circles_name_length check (char_length(trim(name)) between 1 and 80)
);

create table if not exists public.circle_members (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  primary key (circle_id, user_id),
  constraint circle_members_role_check check (role in ('owner', 'admin', 'member'))
);

create table if not exists public.circle_channels (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  name text not null,
  position integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circle_channels_name_length check (char_length(trim(name)) between 1 and 48),
  constraint circle_channels_conversation_unique unique (conversation_id)
);
```

Continue the migration with `circle_posts`, `circle_post_likes`, `circle_post_comments`, indexes, RLS enablement, select policies scoped through `circle_members`, and write RPCs. The RPC names and payload contracts must match the repository methods in Task 3:

```sql
create or replace function public.create_circle(circle_name text, member_ids uuid[] default array[]::uuid[])
returns uuid
```

`create_circle` must insert a Circle, owner membership, friend-only invited members, a `channel` conversation titled `general`, all Circle members as conversation members, and a `circle_channels` row named `general`.

```sql
create or replace function public.list_circle_summaries()
returns table (
  id uuid,
  name text,
  avatar_url text,
  member_count bigint,
  channel_count bigint,
  latest_activity_at timestamptz,
  current_user_role text
)
```

```sql
create or replace function public.get_circle_detail(target_circle_id uuid)
returns jsonb
```

`get_circle_detail` must return a JSON object with keys `circle`, `members`, `channels`, and `posts`.

Add these remaining functions:

```sql
create or replace function public.create_circle_channel(target_circle_id uuid, channel_name text)
returns uuid

create or replace function public.invite_circle_members(target_circle_id uuid, member_ids uuid[])
returns void

create or replace function public.create_circle_post(target_circle_id uuid, body text, attachment jsonb default null)
returns uuid

create or replace function public.toggle_circle_post_like(target_post_id uuid, liked boolean)
returns void

create or replace function public.create_circle_post_comment(target_post_id uuid, body text)
returns uuid

create or replace function public.delete_circle_post(target_post_id uuid)
returns void

create or replace function public.report_circle_post(target_post_id uuid, report_reason text, report_details text default '')
returns uuid
```

Extend reports with nullable `target_post_id uuid references public.circle_posts(id) on delete cascade`, keeping existing user reports valid.

Add discovery and media RPCs:

```sql
create or replace function public.search_discovery(search_query text)
returns table (
  result_type text,
  id uuid,
  title text,
  subtitle text,
  avatar_url text,
  conversation_id uuid,
  circle_id uuid,
  channel_id uuid,
  rank real
)

create or replace function public.list_conversation_media(target_conversation_id uuid)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  type text,
  body text,
  attachment jsonb,
  created_at timestamptz
)
```

Extend `conversations`:

```sql
alter table public.conversations
  add column if not exists announcement_updated_at timestamptz,
  add column if not exists announcement_updated_by uuid references public.profiles(id) on delete set null;
```

Replace `update_group_profile` so changing the announcement also sets `announcement_updated_at = now()` and `announcement_updated_by = auth.uid()`.

- [ ] **Step 4: Run schema tests and verify they pass**

Run:

```bash
rtk flutter test test/supabase/private_chat_schema_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit backend foundation**

Run:

```bash
rtk git add supabase/migrations/202605190003_community_discovery_v1.sql test/supabase/private_chat_schema_test.dart
rtk git commit -m "feat: add community discovery schema"
```

## Task 2: Shared Models

**Files:**
- Create: `lib/shared/models/circle.dart`
- Create: `lib/shared/models/discovery.dart`
- Create: `lib/shared/models/media_attachment.dart`
- Modify: `test/shared/models/private_chat_models_test.dart`

- [ ] **Step 1: Write failing model tests**

Add tests to `test/shared/models/private_chat_models_test.dart`:

```dart
test('circle summary and detail parse rpc payloads', () {
  final summary = CircleSummary.fromJson({
    'id': 'circle-1',
    'name': 'Close Friends',
    'avatar_url': 'circle-avatars/circle-1/a.jpg',
    'member_count': 4,
    'channel_count': 2,
    'latest_activity_at': '2026-05-19T01:02:03Z',
    'current_user_role': 'owner',
  });
  expect(summary.name, 'Close Friends');
  expect(summary.memberCount, 4);
  expect(summary.currentUserRole, 'owner');

  final detail = CircleDetail.fromJson({
    'circle': summary.toJson(),
    'members': [
      {
        'role': 'owner',
        'profile': {
          'id': 'user-1',
          'username': 'xu',
          'display_name': 'Xu',
          'bio': '',
          'created_at': '2026-05-19T01:00:00Z',
          'updated_at': '2026-05-19T01:00:00Z',
        },
      },
    ],
    'channels': [
      {
        'id': 'channel-1',
        'circle_id': 'circle-1',
        'conversation_id': 'conversation-1',
        'name': 'general',
        'position': 0,
      },
    ],
    'posts': const [],
  });
  expect(detail.channels.single.name, 'general');
  expect(detail.canManageCircle, isTrue);
});

test('discovery and media models parse rpc rows', () {
  final result = DiscoveryResult.fromJson({
    'result_type': 'circle_channel',
    'id': 'channel-1',
    'title': 'general',
    'subtitle': 'Close Friends',
    'conversation_id': 'conversation-1',
    'circle_id': 'circle-1',
    'channel_id': 'channel-1',
    'rank': 0.8,
  });
  expect(result.type, DiscoveryResultType.circleChannel);
  expect(result.conversationId, 'conversation-1');

  final media = ConversationMediaItem.fromJson({
    'message_id': 'message-1',
    'conversation_id': 'conversation-1',
    'sender_id': 'user-1',
    'sender_name': 'Xu',
    'type': 'image',
    'body': '',
    'attachment': {
      'kind': 'image',
      'bucket': 'chat-media',
      'path': 'conversation-1/image.jpg',
      'mime_type': 'image/jpeg',
      'size': 123,
    },
    'created_at': '2026-05-19T01:02:03Z',
  });
  expect(media.type, MessageType.image);
  expect(media.imageAttachment?.path, 'conversation-1/image.jpg');
});
```

- [ ] **Step 2: Run model tests and verify they fail**

Run:

```bash
rtk flutter test test/shared/models/private_chat_models_test.dart
```

Expected: FAIL because `CircleSummary`, `DiscoveryResult`, and `ConversationMediaItem` are not defined.

- [ ] **Step 3: Add models**

Create `lib/shared/models/circle.dart` with:

```dart
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

class CircleSummary {
  const CircleSummary({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.channelCount,
    this.avatarUrl,
    this.latestActivityAt,
    this.currentUserRole = 'member',
  });

  factory CircleSummary.fromJson(Map<String, dynamic> json) {
    return CircleSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      channelCount: (json['channel_count'] as num?)?.toInt() ?? 0,
      latestActivityAt: _parseOptionalTimestamp(json['latest_activity_at']),
      currentUserRole: json['current_user_role'] as String? ?? 'member',
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final int memberCount;
  final int channelCount;
  final DateTime? latestActivityAt;
  final String currentUserRole;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar_url': avatarUrl,
    'member_count': memberCount,
    'channel_count': channelCount,
    'latest_activity_at': latestActivityAt?.toIso8601String(),
    'current_user_role': currentUserRole,
  };
}
```

Add `CircleDetail`, `CircleMember`, `CircleChannel`, `CirclePost`, and `CirclePostComment` in the same file. `CircleDetail.canManageCircle` must return true for `owner` or `admin`; `CirclePost.imageAttachment` must use `ImageAttachment.fromJson` when attachment kind is `image`.

Create `lib/shared/models/discovery.dart` with `DiscoveryResultType` values `contact`, `group`, `circle`, `circleChannel`, and `message`; parse unknown types as `message` only if the row has `conversation_id`, otherwise throw `ArgumentError`.

Create `lib/shared/models/media_attachment.dart` with `ConversationMediaItem.fromJson`, `imageAttachment`, and `voiceAttachment` getters.

- [ ] **Step 4: Run model tests and format**

Run:

```bash
rtk dart format lib/shared/models/circle.dart lib/shared/models/discovery.dart lib/shared/models/media_attachment.dart test/shared/models/private_chat_models_test.dart
rtk flutter test test/shared/models/private_chat_models_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit models**

Run:

```bash
rtk git add lib/shared/models/circle.dart lib/shared/models/discovery.dart lib/shared/models/media_attachment.dart test/shared/models/private_chat_models_test.dart
rtk git commit -m "feat: add community discovery models"
```

## Task 3: Circle Repository

**Files:**
- Replace: `lib/features/circles/circles_repository.dart`
- Create: `test/features/circles/circles_repository_test.dart`

- [ ] **Step 1: Write failing repository tests**

Create `test/features/circles/circles_repository_test.dart` with a fake data source and tests for:

```dart
test('listCircles maps list_circle_summaries rows', () async {
  final dataSource = FakeCirclesDataSource()
    ..rpcRows['list_circle_summaries'] = [
      {
        'id': 'circle-1',
        'name': 'Close Friends',
        'member_count': 3,
        'channel_count': 1,
        'current_user_role': 'owner',
      },
    ];
  final repository = SupabaseCirclesRepository(dataSource);
  final circles = await repository.listCircles();
  expect(circles.single.name, 'Close Friends');
});

test('createCircle trims name and calls create_circle rpc', () async {
  final dataSource = FakeCirclesDataSource()..rpcValue = 'circle-1';
  final repository = SupabaseCirclesRepository(dataSource);
  final id = await repository.createCircle(name: ' Close Friends ', memberIds: ['u2']);
  expect(id, 'circle-1');
  expect(dataSource.calls.single.functionName, 'create_circle');
  expect(dataSource.calls.single.params, {
    'circle_name': 'Close Friends',
    'member_ids': ['u2'],
  });
});
```

Also test `getCircleDetail`, `createChannel`, `inviteMembers`, `createPost`, `togglePostLike`, `createComment`, `deletePost`, `reportPost`, and `uploadPostImage` payloads.

- [ ] **Step 2: Run repository tests and verify they fail**

Run:

```bash
rtk flutter test test/features/circles/circles_repository_test.dart
```

Expected: FAIL because repository APIs and data source do not exist.

- [ ] **Step 3: Implement repository**

Replace `lib/features/circles/circles_repository.dart` with:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/report_reason.dart';

final circlesRepositoryProvider = Provider<CirclesRepository>((ref) {
  try {
    return SupabaseCirclesRepository(
      SupabaseCirclesDataSource(ref.watch(supabaseClientProvider)),
    );
  } on AssertionError {
    return const UninitializedCirclesRepository();
  }
});

abstract interface class CirclesRepository {
  Future<List<CircleSummary>> listCircles();
  Future<CircleDetail> getCircleDetail(String circleId);
  Future<String> createCircle({required String name, List<String> memberIds});
  Future<String> createChannel({required String circleId, required String name});
  Future<void> inviteMembers({required String circleId, required List<String> memberIds});
  Future<String> createPost({required String circleId, required String body, ImageAttachment? image});
  Future<String> uploadPostImage({required String circleId, required ChatImageUpload image});
  Future<void> togglePostLike({required String postId, required bool liked});
  Future<String> createComment({required String postId, required String body});
  Future<void> deletePost(String postId);
  Future<void> reportPost({required String postId, required ReportReason reason, String details});
  Future<String> createImageUrl(ImageAttachment attachment);
  Stream<void> circleChanges(String circleId);
}
```

Use a small `CirclesDataSource` with `rpc`, `uploadBinary`, `createSignedUrl`, and `circleChanges`. Storage paths for post images should be `circleId/<timestamp>-<safeFileName>`, bucket `chat-media`, matching existing attachment shape.

- [ ] **Step 4: Run repository tests and format**

Run:

```bash
rtk dart format lib/features/circles/circles_repository.dart test/features/circles/circles_repository_test.dart
rtk flutter test test/features/circles/circles_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit repository**

Run:

```bash
rtk git add lib/features/circles/circles_repository.dart test/features/circles/circles_repository_test.dart
rtk git commit -m "feat: add circles repository"
```

## Task 4: Circle List, Creation, Detail, Channels

**Files:**
- Replace: `lib/features/circles/circles_screen.dart`
- Create: `lib/features/circles/circle_creation_sheet.dart`
- Create: `lib/features/circles/circle_detail_screen.dart`
- Create: `lib/features/circles/circle_channel_creation_sheet.dart`
- Create: `lib/features/circles/circle_invite_sheet.dart`
- Modify: `lib/shared/navigation/app_router.dart`
- Modify: `test/features/circles/circles_screen_test.dart`
- Create: `test/features/circles/circle_detail_screen_test.dart`
- Modify: `test/shared/navigation/app_router_test.dart`

- [ ] **Step 1: Write failing widget/navigation tests**

Update `test/features/circles/circles_screen_test.dart` to cover:

```dart
testWidgets('creates a circle from the empty state', (tester) async {
  final repository = FakeCirclesRepository()..createdCircleId = 'circle-1';
  await tester.pumpWidget(buildCirclesApp(repository));
  await tester.tap(find.text('Create Circle'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'Close Friends');
  await tester.tap(find.text('Create'));
  await tester.pumpAndSettle();
  expect(repository.createCalls.single.name, 'Close Friends');
});
```

Create `test/features/circles/circle_detail_screen_test.dart` with tests for rendering channels/feed tabs, opening a channel, creating a channel, and inviting members.

Update router tests to assert `/circles/circle-1` opens `CircleDetailScreen` and `/chats/conversation-1/media` opens `ChatMediaScreen` after Task 7.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
rtk flutter test test/features/circles/circles_screen_test.dart test/features/circles/circle_detail_screen_test.dart test/shared/navigation/app_router_test.dart
```

Expected: FAIL because screens/routes do not exist.

- [ ] **Step 3: Implement Circle screens**

Update `CirclesScreen`:

- Use `FutureBuilder<List<CircleSummary>>`.
- Empty state button opens `CircleCreationSheet`.
- List rows show avatar fallback, name, member count, channel count, and latest activity.
- Tapping a Circle goes to `/circles/:circleId`.

Create `CircleCreationSheet`:

- Text field label `Circle name`.
- Optional friend picker using `contactsRepositoryProvider.listFriends()`.
- Submit calls `circlesRepositoryProvider.createCircle`.
- Inline error text: `Could not create Circle. Try again.`

Create `CircleDetailScreen`:

- Route constructor `CircleDetailScreen({required this.circleId, super.key})`.
- AppBar title from detail name.
- Tabs: `Channels`, `Feed`.
- Channels tab lists `CircleChannel` rows; tapping uses `context.go('${ChatsScreen.path}/${channel.conversationId}', extra: ChatThreadRouteExtra(title: '# ${channel.name}', type: ConversationType.channel))`.
- Owner/admin sees icon buttons for invite and create channel.

Create `CircleChannelCreationSheet` and `CircleInviteSheet` with inline errors and disabled submit while saving.

Update `app_router.dart`:

```dart
GoRoute(
  path: '${CirclesScreen.path}/:circleId',
  builder: (context, state) => CircleDetailScreen(
    circleId: state.pathParameters['circleId']!,
  ),
),
```

- [ ] **Step 4: Run tests and format**

Run:

```bash
rtk dart format lib/features/circles lib/shared/navigation/app_router.dart test/features/circles test/shared/navigation/app_router_test.dart
rtk flutter test test/features/circles/circles_screen_test.dart test/features/circles/circle_detail_screen_test.dart test/shared/navigation/app_router_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Circle UI foundation**

Run:

```bash
rtk git add lib/features/circles lib/shared/navigation/app_router.dart test/features/circles test/shared/navigation/app_router_test.dart
rtk git commit -m "feat: add circles channels UI"
```

## Task 5: Circle Feed

**Files:**
- Create: `lib/features/circles/circle_feed_composer.dart`
- Create: `lib/features/circles/circle_post_tile.dart`
- Modify: `lib/features/circles/circle_detail_screen.dart`
- Create: `test/features/circles/circle_feed_test.dart`

- [ ] **Step 1: Write failing feed tests**

Create tests that verify:

- Feed tab renders posts with author, body, image, like count, comment count.
- Composer sends trimmed text.
- Composer uploads and sends image attachment.
- Like button calls `togglePostLike(postId, liked: true)` and unlike calls false.
- Comment action calls `createComment`.
- Delete is visible for own posts and calls `deletePost`.
- Report is visible for other users and calls `reportPost`.

Use `FakeCirclesRepository` with call lists for each action.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
rtk flutter test test/features/circles/circle_feed_test.dart
```

Expected: FAIL because feed widgets do not exist.

- [ ] **Step 3: Implement feed widgets**

`CircleFeedComposer`:

- TextField label `Share something`.
- Image icon button reuses `imagePickerServiceProvider`.
- Submit disabled for empty text with no image.
- Calls `uploadPostImage` before `createPost` when image selected.
- Shows `Could not share post. Try again.` with the root error appended in debug-style text matching current image-message behavior.

`CirclePostTile`:

- Header: author avatar/name and time.
- Body text.
- Image preview using signed URL from `createImageUrl`.
- Actions: Like/Unlike, Comment, Delete own post, Report other post.
- Comments render below the post.

Integrate into `CircleDetailScreen` Feed tab and refresh detail after successful writes by invalidating the detail provider or reloading the local future.

- [ ] **Step 4: Run feed tests and format**

Run:

```bash
rtk dart format lib/features/circles test/features/circles/circle_feed_test.dart
rtk flutter test test/features/circles/circle_feed_test.dart test/features/circles/circle_detail_screen_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Circle feed**

Run:

```bash
rtk git add lib/features/circles test/features/circles
rtk git commit -m "feat: add circle feed"
```

## Task 6: Group Announcement Polish

**Files:**
- Modify: `lib/features/groups/group_detail_sheet.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `lib/features/chats/chats_repository.dart`
- Modify: `test/features/groups/group_detail_sheet_test.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`
- Modify: `test/features/chats/chats_repository_test.dart`

- [ ] **Step 1: Write failing group announcement tests**

Add tests:

```dart
testWidgets('group chat shows announcement strip when present', (tester) async {
  final repository = FakeChatsRepository(
    groupDetail: GroupDetail(
      conversationId: 'group-1',
      title: 'Trip',
      announcement: 'Meet at 7',
      currentUserRole: 'member',
      members: const [],
    ),
  );
  await tester.pumpWidget(buildChatThread(repository, conversationType: ConversationType.group));
  await tester.pumpAndSettle();
  expect(find.text('Meet at 7'), findsOneWidget);
});
```

Add group detail tests for admin editable announcement and member read-only announcement.

- [ ] **Step 2: Run tests and verify they fail where behavior is missing**

Run:

```bash
rtk flutter test test/features/groups/group_detail_sheet_test.dart test/features/chats/chat_thread_screen_test.dart test/features/chats/chats_repository_test.dart
```

Expected: FAIL for missing announcement strip or metadata assertions.

- [ ] **Step 3: Implement announcement polish**

- Ensure `GroupDetail.fromJson` or repository mapping includes `announcement`, `announcement_updated_at`, and updater display data when available.
- Keep `GroupDetailSheet` save behavior on `updateGroupProfile`.
- Add a compact strip in `ChatThreadScreen` under the app bar content for group conversations with non-empty announcement.
- Strip text max two lines with an announcement icon; tapping opens `GroupDetailSheet`.

- [ ] **Step 4: Run targeted tests and format**

Run:

```bash
rtk dart format lib/features/groups/group_detail_sheet.dart lib/features/chats/chat_thread_screen.dart lib/features/chats/chats_repository.dart test/features/groups/group_detail_sheet_test.dart test/features/chats/chat_thread_screen_test.dart test/features/chats/chats_repository_test.dart
rtk flutter test test/features/groups/group_detail_sheet_test.dart test/features/chats/chat_thread_screen_test.dart test/features/chats/chats_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit announcements**

Run:

```bash
rtk git add lib/features/groups/group_detail_sheet.dart lib/features/chats/chat_thread_screen.dart lib/features/chats/chats_repository.dart test/features/groups/group_detail_sheet_test.dart test/features/chats/chat_thread_screen_test.dart test/features/chats/chats_repository_test.dart
rtk git commit -m "feat: polish group announcements"
```

## Task 7: Global Discovery

**Files:**
- Modify: `lib/features/chats/chats_repository.dart`
- Modify: `lib/features/chats/global_message_search_screen.dart`
- Modify: `test/features/chats/global_message_search_screen_test.dart`
- Modify: `test/features/chats/chats_repository_test.dart`

- [ ] **Step 1: Write failing discovery tests**

Add repository test:

```dart
test('searchDiscovery maps grouped discovery rows', () async {
  final dataSource = FakeChatsDataSource()
    ..rpcRows['search_discovery'] = [
      {
        'result_type': 'circle',
        'id': 'circle-1',
        'title': 'Close Friends',
        'subtitle': '3 members',
        'rank': 0.9,
      },
      {
        'result_type': 'message',
        'id': 'message-1',
        'title': 'Trip',
        'subtitle': 'Xu · hello',
        'conversation_id': 'conversation-1',
        'rank': 0.5,
      },
    ];
  final repository = SupabaseChatsRepository(dataSource);
  final results = await repository.searchDiscovery('fri');
  expect(results.first.title, 'Close Friends');
});
```

Update widget test to expect grouped headings: `Contacts`, `Groups`, `Circles`, `Channels`, `Messages`.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
rtk flutter test test/features/chats/chats_repository_test.dart test/features/chats/global_message_search_screen_test.dart
```

Expected: FAIL because `searchDiscovery` and grouped UI do not exist.

- [ ] **Step 3: Implement repository and grouped screen**

In `ChatsRepository`, add:

```dart
Future<List<DiscoveryResult>> searchDiscovery(String query);
```

Implement with RPC `search_discovery` and `DiscoveryResult.fromJson`.

Update `GlobalMessageSearchScreen`:

- Keep `static const path = '/search/messages'` to avoid route churn.
- AppBar title `Search`.
- Search field hint `Search WeCord`.
- Group results by `DiscoveryResultType`.
- Navigate:
  - contact: `/profile/:id`
  - group/message: `/chats/:conversationId`
  - circle: `/circles/:id`
  - circleChannel: `/chats/:conversationId` with channel route extra when available.

- [ ] **Step 4: Run discovery tests and format**

Run:

```bash
rtk dart format lib/features/chats/chats_repository.dart lib/features/chats/global_message_search_screen.dart test/features/chats/chats_repository_test.dart test/features/chats/global_message_search_screen_test.dart
rtk flutter test test/features/chats/chats_repository_test.dart test/features/chats/global_message_search_screen_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit discovery**

Run:

```bash
rtk git add lib/features/chats/chats_repository.dart lib/features/chats/global_message_search_screen.dart test/features/chats/chats_repository_test.dart test/features/chats/global_message_search_screen_test.dart
rtk git commit -m "feat: add grouped discovery search"
```

## Task 8: Chat Media Center

**Files:**
- Create: `lib/features/chats/chat_media_screen.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `lib/features/chats/chats_repository.dart`
- Modify: `lib/shared/navigation/app_router.dart`
- Create: `test/features/chats/chat_media_screen_test.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`
- Modify: `test/shared/navigation/app_router_test.dart`

- [ ] **Step 1: Write failing media center tests**

Create `test/features/chats/chat_media_screen_test.dart`:

```dart
testWidgets('media center renders image and voice attachments', (tester) async {
  final repository = FakeChatsRepository()
    ..mediaItems = [
      ConversationMediaItem(
        messageId: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        senderName: 'Xu',
        type: MessageType.image,
        body: '',
        attachment: const {
          'kind': 'image',
          'bucket': 'chat-media',
          'path': 'c1/image.jpg',
          'mime_type': 'image/jpeg',
          'size': 100,
        },
        createdAt: DateTime.utc(2026, 5, 19),
      ),
    ];
  await tester.pumpWidget(buildMediaApp(repository));
  await tester.pumpAndSettle();
  expect(find.text('Images'), findsOneWidget);
  expect(find.text('Xu'), findsOneWidget);
});
```

Add chat thread test that app bar menu contains `Media` and navigates to `/chats/:conversationId/media`.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
rtk flutter test test/features/chats/chat_media_screen_test.dart test/features/chats/chat_thread_screen_test.dart test/shared/navigation/app_router_test.dart
```

Expected: FAIL because media route/screen/repository API do not exist.

- [ ] **Step 3: Implement media center**

In `ChatsRepository`, add:

```dart
Future<List<ConversationMediaItem>> listConversationMedia(String conversationId);
```

Implement with RPC `list_conversation_media`.

Create `ChatMediaScreen`:

- Constructor `ChatMediaScreen({required this.conversationId, super.key})`.
- AppBar title `Media`.
- Tabs or segmented filter for `Images`, `Voice`, `Files`.
- Image rows use signed URL and open the existing image preview pattern from chat bubbles.
- Voice rows use `VoiceMessagePlayer`.
- Empty state `No media yet`.

Update router:

```dart
GoRoute(
  path: '/chats/:conversationId/media',
  builder: (context, state) => ChatMediaScreen(
    conversationId: state.pathParameters['conversationId']!,
  ),
),
```

Update `ChatThreadScreen` app bar actions with a media icon button for every conversation.

- [ ] **Step 4: Run media tests and format**

Run:

```bash
rtk dart format lib/features/chats/chat_media_screen.dart lib/features/chats/chat_thread_screen.dart lib/features/chats/chats_repository.dart lib/shared/navigation/app_router.dart test/features/chats/chat_media_screen_test.dart test/features/chats/chat_thread_screen_test.dart test/shared/navigation/app_router_test.dart
rtk flutter test test/features/chats/chat_media_screen_test.dart test/features/chats/chat_thread_screen_test.dart test/shared/navigation/app_router_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit media center**

Run:

```bash
rtk git add lib/features/chats/chat_media_screen.dart lib/features/chats/chat_thread_screen.dart lib/features/chats/chats_repository.dart lib/shared/navigation/app_router.dart test/features/chats/chat_media_screen_test.dart test/features/chats/chat_thread_screen_test.dart test/shared/navigation/app_router_test.dart
rtk git commit -m "feat: add chat media center"
```

## Task 9: Integration, Remote Migration, Full Verification

**Files:**
- Modify only files required by integration failures.
- Update `README.md` if it currently tracks milestones.

- [ ] **Step 1: Run full local verification**

Run:

```bash
rtk flutter analyze
rtk flutter test
```

Expected: analyze reports no issues and all tests pass.

- [ ] **Step 2: Push Supabase migration**

Run:

```bash
rtk supabase migration list
rtk supabase db push --yes
rtk supabase migration list
```

Expected: before push, `202605190003` appears local-only; after push, `202605190003` appears on both Local and Remote.

- [ ] **Step 3: Spot-check remote schema**

Run:

```bash
rtk supabase db query --linked "select table_name from information_schema.tables where table_schema = 'public' and table_name in ('circles','circle_members','circle_channels','circle_posts','circle_post_likes','circle_post_comments') order by table_name;"
rtk supabase db query --linked "select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and proname in ('create_circle','get_circle_detail','search_discovery','list_conversation_media') order by proname;"
```

Expected: all six tables and all four functions are returned.

- [ ] **Step 4: Run final verification after remote push**

Run:

```bash
rtk flutter analyze
rtk flutter test
rtk git status --short
```

Expected: analyze clean, all tests pass, and status only contains intentional changes.

- [ ] **Step 5: Commit final integration fixes**

If Step 4 produced code fixes, commit them:

```bash
rtk git add -A
rtk git commit -m "chore: verify community discovery v1"
```

If no files changed after the prior task commits, do not create an empty commit.

- [ ] **Step 6: Push branch**

Run:

```bash
rtk git push -u origin wecord-foundation
```

Expected: branch pushes successfully.

## Self-Review Checklist

- Spec coverage: Circle creation, members, channels, feed, group announcements, discovery, media center, and remote migration verification are covered.
- Vague-step scan: no task contains an unfinished marker or an undefined "handle later" implementation step.
- Type consistency: Circle, discovery, and media model names match repository and widget tasks.
- Isolation: backend/models/repository/UI/feed/group/discovery/media are separate enough for subagents with limited overlap.
