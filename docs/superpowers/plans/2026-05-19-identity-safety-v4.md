# WeCord Identity & Safety v4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user profile pages, block/report/privacy flows, and a starter Circles shell so WeCord has a real identity and safety layer before larger social features.

**Architecture:** Keep all sensitive relationship writes behind narrow Supabase RPCs, then expose them through small repository methods and focused UI surfaces. Profile pages become the shared entry point from contacts, chats, groups, and future circles. Circles stays intentionally light in this milestone: visible navigation, empty/creation shell, and data contracts only where they support the next milestone.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase Auth/Postgres/RLS/RPC, Flutter widget/unit tests, SQL migration text tests.

---

## Scope

### In Scope

- Public profile page for any user visible to the current user.
- Profile actions: start chat, add friend, accept/reject pending request, set alias, block, unblock, report.
- Block enforcement in friend request creation and direct conversation creation.
- Block list and privacy entry points in Settings.
- Basic report RPC and table access.
- Circles starter shell: real empty state, create-entry UI, model/repository boundaries, and disabled/informational placeholders for channels.

### Out Of Scope

- Full circle channels, channel conversations, roles, notifications, or live voice rooms.
- Remote push notification changes.
- End-to-end encryption.
- Moderation admin dashboard.
- Public discovery or public circles.

## Current Context

- Existing route shell already includes `CirclesScreen.path`.
- `public.blocks` exists from `202605180001_private_chat.sql`, but app-level block UX is missing.
- `reports` appears in the original product design but has no implemented table/RPC yet.
- `Profile.alias` and `Profile.displayLabel` already exist from Daily Chat Polish v3.
- Current dirty files before this milestone: `ios/Podfile.lock` and `macos/Podfile.lock`, changed by local pod install after voice-message dependencies. Treat them as pre-existing local changes and do not revert.

## File Structure

- Create `supabase/migrations/202605190001_identity_safety_v4.sql`: report table, privacy settings, profile summary RPCs, block/unblock/report RPCs, and stricter friend/direct checks.
- Modify `test/supabase/private_chat_schema_test.dart`: assert privacy/safety contracts and RLS boundaries.
- Create `lib/shared/models/profile_relationship.dart`: enum/value object for friendship/block/request status.
- Create `lib/shared/models/report_reason.dart`: typed report reasons.
- Modify `test/shared/models/private_chat_models_test.dart`: parse relationship/status/report metadata.
- Create `lib/features/profile/profile_repository.dart`: profile summary, relationship actions, report/block APIs.
- Create `lib/features/profile/user_profile_screen.dart`: profile page and action surface.
- Create `lib/features/profile/report_user_sheet.dart`: report reason/details form.
- Modify `lib/shared/navigation/app_router.dart`: add `/profile/:userId`.
- Modify `lib/features/contacts/contacts_screen.dart`: open profile from friend/search/request rows.
- Modify `lib/features/chats/chat_thread_screen.dart`: open peer/group member profiles from avatars and member lists.
- Modify `lib/features/groups/group_detail_sheet.dart`: member row opens profile.
- Modify `lib/features/settings/settings_repository.dart`: list blocked users and privacy settings APIs.
- Modify `lib/features/settings/settings_screen.dart`: privacy/safety section with block list.
- Create `lib/features/circles/circles_repository.dart`: starter repository boundary for future circles.
- Modify `lib/features/circles/circles_screen.dart`: richer starter shell and create-circle placeholder flow.
- Add focused tests under `test/features/profile`, `test/features/settings`, and `test/features/circles`.

---

## Task 1: Backend Safety Contracts

**Files:**
- Create: `supabase/migrations/202605190001_identity_safety_v4.sql`
- Modify: `test/supabase/private_chat_schema_test.dart`

- [ ] **Step 1: Write failing schema tests**

Add these tests near the existing social/privacy migration tests in `test/supabase/private_chat_schema_test.dart`:

```dart
test('identity safety v4 adds narrow profile safety RPCs', () {
  final sql = allMigrationSql();

  expect(sql, contains('create table if not exists public.user_privacy_settings'));
  expect(sql, contains('create table if not exists public.reports'));
  expect(sql, contains('create or replace function public.get_profile_summary'));
  expect(sql, contains('create or replace function public.block_user'));
  expect(sql, contains('create or replace function public.unblock_user'));
  expect(sql, contains('create or replace function public.report_user'));

  final blockBody = functionBody(sql, 'block_user');
  expect(blockBody, contains('auth.uid()'));
  expect(blockBody, contains('blocked_id <> auth.uid()'));
  expect(blockBody, contains('delete from public.friend_requests'));

  final reportBody = functionBody(sql, 'report_user');
  expect(reportBody, contains('target_user_id <> auth.uid()'));
  expect(reportBody, contains('insert into public.reports'));
});

test('identity safety v4 enforces blocks before social writes', () {
  final sql = allMigrationSql();

  final friendBody = functionBody(sql, 'send_friend_request');
  expect(friendBody, contains('public.are_users_blocked'));

  final directBody = functionBody(sql, 'get_or_create_direct_conversation');
  expect(directBody, contains('public.are_users_blocked'));

  final profileBody = functionBody(sql, 'get_profile_summary');
  expect(profileBody, contains('relationship_status'));
  expect(profileBody, contains('is_blocked_by_me'));
  expect(profileBody, contains('has_blocked_me'));
});
```

- [ ] **Step 2: Run schema tests and verify failure**

Run:

```bash
rtk flutter test test/supabase/private_chat_schema_test.dart
```

Expected: FAIL because `identity_safety_v4`, `get_profile_summary`, `block_user`, `unblock_user`, and `report_user` do not exist yet.

- [ ] **Step 3: Add the migration**

Create `supabase/migrations/202605190001_identity_safety_v4.sql` with:

```sql
create table if not exists public.user_privacy_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  friend_request_policy text not null default 'everyone'
    check (friend_request_policy in ('everyone', 'friends_of_friends', 'none')),
  show_online_status boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('spam', 'harassment', 'impersonation', 'unsafe_content', 'other')),
  details text not null default '',
  status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now(),
  constraint reports_not_self check (reporter_id <> target_user_id)
);

alter table public.user_privacy_settings enable row level security;
alter table public.reports enable row level security;

create policy user_privacy_settings_select_owner
  on public.user_privacy_settings for select
  to authenticated
  using (user_id = auth.uid());

create policy reports_select_reporter
  on public.reports for select
  to authenticated
  using (reporter_id = auth.uid());

create or replace function public.are_users_blocked(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocks b
    where (b.blocker_id = user_a and b.blocked_id = user_b)
       or (b.blocker_id = user_b and b.blocked_id = user_a)
  );
$$;

create or replace function public.get_profile_summary(target_user_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  alias text,
  avatar_url text,
  bio text,
  relationship_status text,
  incoming_request_id uuid,
  outgoing_request_id uuid,
  is_blocked_by_me boolean,
  has_blocked_me boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with friendship as (
    select 1
    from public.friendships f
    where f.user_low_id = least(auth.uid(), target_user_id)
      and f.user_high_id = greatest(auth.uid(), target_user_id)
  ),
  incoming_request as (
    select fr.id
    from public.friend_requests fr
    where fr.requester_id = target_user_id
      and fr.receiver_id = auth.uid()
      and fr.status = 'pending'
    order by fr.created_at desc
    limit 1
  ),
  outgoing_request as (
    select fr.id
    from public.friend_requests fr
    where fr.requester_id = auth.uid()
      and fr.receiver_id = target_user_id
      and fr.status = 'pending'
    order by fr.created_at desc
    limit 1
  ),
  block_state as (
    select
      exists (
        select 1 from public.blocks b
        where b.blocker_id = auth.uid()
          and b.blocked_id = target_user_id
      ) as is_blocked_by_me,
      exists (
        select 1 from public.blocks b
        where b.blocker_id = target_user_id
          and b.blocked_id = auth.uid()
      ) as has_blocked_me
  )
  select
    p.id,
    p.username,
    p.display_name,
    ca.alias,
    p.avatar_url,
    case when bs.has_blocked_me then '' else p.bio end as bio,
    case
      when p.id = auth.uid() then 'self'
      when bs.is_blocked_by_me then 'blocked'
      when bs.has_blocked_me then 'blocked_by_them'
      when exists (select 1 from friendship) then 'friend'
      when exists (select 1 from incoming_request) then 'incoming_request'
      when exists (select 1 from outgoing_request) then 'outgoing_request'
      else 'none'
    end as relationship_status,
    (select id from incoming_request) as incoming_request_id,
    (select id from outgoing_request) as outgoing_request_id,
    bs.is_blocked_by_me,
    bs.has_blocked_me
  from public.profiles p
  cross join block_state bs
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where p.id = target_user_id;
$$;

create or replace function public.block_user(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if target_user_id = auth.uid() then
    raise exception 'Cannot block yourself' using errcode = '23514';
  end if;

  insert into public.blocks (blocker_id, blocked_id)
  values (auth.uid(), target_user_id)
  on conflict (blocker_id, blocked_id) do nothing;

  delete from public.friend_requests
  where status = 'pending'
    and (
      (requester_id = auth.uid() and receiver_id = target_user_id)
      or (requester_id = target_user_id and receiver_id = auth.uid())
    );
end;
$$;

create or replace function public.unblock_user(target_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.blocks
  where blocker_id = auth.uid()
    and blocked_id = target_user_id;
$$;

create or replace function public.report_user(
  target_user_id uuid,
  report_reason text,
  report_details text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_report_id uuid;
begin
  if target_user_id = auth.uid() then
    raise exception 'Cannot report yourself' using errcode = '23514';
  end if;

  insert into public.reports (reporter_id, target_user_id, reason, details)
  values (
    auth.uid(),
    target_user_id,
    report_reason,
    left(coalesce(report_details, ''), 1000)
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;
```

- [ ] **Step 4: Update social-write RPCs to enforce blocks**

In the same migration, replace `send_friend_request` and `get_or_create_direct_conversation` with `create or replace function` definitions that preserve the existing behavior but add:

```sql
if public.are_users_blocked(auth.uid(), receiver_id) then
  raise exception 'Cannot send friend request' using errcode = '42501';
end if;
```

and:

```sql
if public.are_users_blocked(auth.uid(), other_user_id) then
  raise exception 'Cannot create direct conversation' using errcode = '42501';
end if;
```

Copy the current function bodies from `supabase/migrations/202605180001_private_chat.sql`, then make only those guard additions.

- [ ] **Step 5: Run schema tests**

Run:

```bash
rtk flutter test test/supabase/private_chat_schema_test.dart
```

Expected: PASS.

---

## Task 2: Domain Models And Profile Repository

**Files:**
- Create: `lib/shared/models/profile_relationship.dart`
- Create: `lib/shared/models/report_reason.dart`
- Create: `lib/features/profile/profile_repository.dart`
- Modify: `test/shared/models/private_chat_models_test.dart`
- Create: `test/features/profile/profile_repository_test.dart`

- [ ] **Step 1: Add failing model tests**

Add to `test/shared/models/private_chat_models_test.dart`:

```dart
test('ProfileRelationship parses profile summary status fields', () {
  final summary = ProfileSummary.fromJson({
    'id': 'user-2',
    'username': 'ada',
    'display_name': 'Ada',
    'alias': 'A',
    'avatar_url': null,
    'bio': 'math',
    'relationship_status': 'friend',
    'incoming_request_id': null,
    'outgoing_request_id': null,
    'is_blocked_by_me': false,
    'has_blocked_me': false,
  });

  expect(summary.profile.displayLabel, 'A');
  expect(summary.relationshipStatus, ProfileRelationshipStatus.friend);
  expect(summary.canStartChat, isTrue);
  expect(summary.canSendFriendRequest, isFalse);
});
```

- [ ] **Step 2: Add model files**

Create `lib/shared/models/profile_relationship.dart`:

```dart
import 'package:wecord/shared/models/profile.dart';

enum ProfileRelationshipStatus {
  self,
  none,
  friend,
  incomingRequest,
  outgoingRequest,
  blocked,
  blockedByThem;

  static ProfileRelationshipStatus fromJson(String? value) {
    return switch (value) {
      'self' => ProfileRelationshipStatus.self,
      'friend' => ProfileRelationshipStatus.friend,
      'incoming_request' => ProfileRelationshipStatus.incomingRequest,
      'outgoing_request' => ProfileRelationshipStatus.outgoingRequest,
      'blocked' => ProfileRelationshipStatus.blocked,
      'blocked_by_them' => ProfileRelationshipStatus.blockedByThem,
      _ => ProfileRelationshipStatus.none,
    };
  }
}

class ProfileSummary {
  const ProfileSummary({
    required this.profile,
    required this.relationshipStatus,
    required this.incomingRequestId,
    required this.outgoingRequestId,
    required this.isBlockedByMe,
    required this.hasBlockedMe,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      profile: Profile.fromJson(json),
      relationshipStatus: ProfileRelationshipStatus.fromJson(
        json['relationship_status'] as String?,
      ),
      incomingRequestId: json['incoming_request_id'] as String?,
      outgoingRequestId: json['outgoing_request_id'] as String?,
      isBlockedByMe: json['is_blocked_by_me'] as bool? ?? false,
      hasBlockedMe: json['has_blocked_me'] as bool? ?? false,
    );
  }

  final Profile profile;
  final ProfileRelationshipStatus relationshipStatus;
  final String? incomingRequestId;
  final String? outgoingRequestId;
  final bool isBlockedByMe;
  final bool hasBlockedMe;

  bool get canStartChat => relationshipStatus == ProfileRelationshipStatus.friend;
  bool get canSendFriendRequest => relationshipStatus == ProfileRelationshipStatus.none;
  bool get canAcceptRequest =>
      relationshipStatus == ProfileRelationshipStatus.incomingRequest &&
      incomingRequestId != null;
}
```

Create `lib/shared/models/report_reason.dart`:

```dart
enum ReportReason {
  spam('spam', 'Spam'),
  harassment('harassment', 'Harassment'),
  impersonation('impersonation', 'Impersonation'),
  unsafeContent('unsafe_content', 'Unsafe content'),
  other('other', 'Other');

  const ReportReason(this.value, this.label);

  final String value;
  final String label;
}
```

- [ ] **Step 3: Add failing repository tests**

Create `test/features/profile/profile_repository_test.dart` with fake data source tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  test('getProfileSummary calls scoped RPC and parses one row', () async {
    final dataSource = FakeProfileDataSource()
      ..rpcResult = [
        {
          'id': 'user-2',
          'username': 'ada',
          'display_name': 'Ada',
          'alias': null,
          'avatar_url': null,
          'bio': '',
          'relationship_status': 'none',
          'incoming_request_id': null,
          'outgoing_request_id': null,
          'is_blocked_by_me': false,
          'has_blocked_me': false,
        },
      ];
    final repository = ProfileRepository.withDataSource(dataSource);

    final summary = await repository.getProfileSummary('user-2');

    expect(summary.profile.username, 'ada');
    expect(dataSource.calls.single.name, 'get_profile_summary');
    expect(dataSource.calls.single.params, {'target_user_id': 'user-2'});
  });

  test('block report and unblock use narrow RPCs', () async {
    final dataSource = FakeProfileDataSource();
    final repository = ProfileRepository.withDataSource(dataSource);

    await repository.blockUser('user-2');
    await repository.reportUser(
      targetUserId: 'user-2',
      reason: ReportReason.spam,
      details: 'Repeated invites',
    );
    await repository.unblockUser('user-2');

    expect(dataSource.calls.map((call) => call.name), [
      'block_user',
      'report_user',
      'unblock_user',
    ]);
  });
}

class RpcCall {
  const RpcCall(this.name, this.params);
  final String name;
  final Map<String, dynamic> params;
}

class FakeProfileDataSource implements ProfileDataSource {
  Object? rpcResult;
  final calls = <RpcCall>[];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add(RpcCall(functionName, params));
    return rpcResult;
  }
}
```

- [ ] **Step 4: Implement repository**

Create `lib/features/profile/profile_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/profile_relationship.dart';
import 'package:wecord/shared/models/report_reason.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(SupabaseProfileDataSource(ref.watch(supabaseClientProvider)));
});

abstract interface class ProfileDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);
}

class ProfileRepository {
  const ProfileRepository(this._dataSource);

  const ProfileRepository.withDataSource(this._dataSource);

  final ProfileDataSource _dataSource;

  Future<ProfileSummary> getProfileSummary(String userId) async {
    final rows = await _dataSource.rpc('get_profile_summary', {
      'target_user_id': userId,
    });
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) {
      throw StateError('Profile not found.');
    }
    return ProfileSummary.fromJson(list.single);
  }

  Future<void> blockUser(String userId) {
    return _dataSource.rpc('block_user', {'target_user_id': userId});
  }

  Future<void> unblockUser(String userId) {
    return _dataSource.rpc('unblock_user', {'target_user_id': userId});
  }

  Future<void> reportUser({
    required String targetUserId,
    required ReportReason reason,
    required String details,
  }) {
    return _dataSource.rpc('report_user', {
      'target_user_id': targetUserId,
      'report_reason': reason.value,
      'report_details': details,
    });
  }
}

class SupabaseProfileDataSource implements ProfileDataSource {
  const SupabaseProfileDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc(functionName, params: params);
  }
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
rtk flutter test test/shared/models/private_chat_models_test.dart test/features/profile/profile_repository_test.dart
```

Expected: PASS.

---

## Task 3: User Profile Screen And Navigation

**Files:**
- Create: `lib/features/profile/user_profile_screen.dart`
- Create: `lib/features/profile/report_user_sheet.dart`
- Modify: `lib/shared/navigation/app_router.dart`
- Modify: `lib/features/contacts/contacts_screen.dart`
- Modify: `lib/features/groups/group_detail_sheet.dart`
- Test: `test/features/profile/user_profile_screen_test.dart`
- Test: `test/shared/navigation/app_router_test.dart`

- [ ] **Step 1: Add route tests**

Add to `test/shared/navigation/app_router_test.dart`:

```dart
testWidgets('routes signed-in users to profile pages', (tester) async {
  final router = buildTestRouter(authState: signedInState);

  router.go('/profile/user-2');
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();

  expect(find.text('Profile'), findsOneWidget);
});
```

- [ ] **Step 2: Add screen tests**

Create `test/features/profile/user_profile_screen_test.dart` with provider overrides for a fake `ProfileRepository`:

```dart
testWidgets('profile page shows friend actions', (tester) async {
  await tester.pumpWidget(buildProfileHarness(
    summary: friendSummary(displayName: 'Ada', username: 'ada'),
  ));

  expect(find.text('Ada'), findsOneWidget);
  expect(find.text('@ada'), findsOneWidget);
  expect(find.text('Message'), findsOneWidget);
  expect(find.text('Block'), findsOneWidget);
  expect(find.text('Report'), findsOneWidget);
});

testWidgets('profile page shows add friend action for non-friends', (tester) async {
  await tester.pumpWidget(buildProfileHarness(
    summary: noneSummary(displayName: 'Grace', username: 'grace'),
  ));

  expect(find.text('Add Friend'), findsOneWidget);
  expect(find.text('Message'), findsNothing);
});
```

Use existing test harness patterns from `test/features/contacts/contacts_screen_test.dart`.

- [ ] **Step 3: Add profile route**

In `lib/shared/navigation/app_router.dart`, import `UserProfileScreen` and add:

```dart
GoRoute(
  path: '${UserProfileScreen.path}/:userId',
  builder: (context, state) {
    return UserProfileScreen(userId: state.pathParameters['userId']!);
  },
),
```

Define `UserProfileScreen.path = '/profile'`.

- [ ] **Step 4: Implement `UserProfileScreen`**

Create `lib/features/profile/user_profile_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/report_user_sheet.dart';
import 'package:wecord/shared/models/profile_relationship.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({required this.userId, super.key});

  static const path = '/profile';

  final String userId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  late Future<ProfileSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _summaryFuture = ref.read(profileRepositoryProvider).getProfileSummary(widget.userId);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        setState(_reload);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update profile action. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<ProfileSummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: FilledButton(
                onPressed: () => setState(_reload),
                child: const Text('Try again'),
              ),
            );
          }
          final summary = snapshot.data!;
          final profile = summary.profile;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              CircleAvatar(radius: 40, child: Text(profile.displayLabel.characters.first.toUpperCase())),
              const SizedBox(height: 16),
              Text(profile.displayLabel, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              Text('@${profile.username}', textAlign: TextAlign.center),
              if (profile.bio.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(profile.bio, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              if (summary.canStartChat)
                FilledButton(
                  onPressed: () async {
                    final conversation = await ref
                        .read(chatsRepositoryProvider)
                        .createOrGetDirectConversation(profile.id);
                    if (context.mounted) {
                      context.go('/chats/${conversation.id}', extra: conversation);
                    }
                  },
                  child: const Text('Message'),
                ),
              if (summary.canSendFriendRequest)
                FilledButton(
                  onPressed: () => _run(
                    () => ref.read(contactsRepositoryProvider).sendFriendRequest(profile.id),
                  ),
                  child: const Text('Add Friend'),
                ),
              if (summary.canAcceptRequest)
                FilledButton(
                  onPressed: () => _run(
                    () => ref.read(contactsRepositoryProvider).acceptFriendRequest(summary.incomingRequestId!),
                  ),
                  child: const Text('Accept Request'),
                ),
              if (summary.relationshipStatus == ProfileRelationshipStatus.blocked)
                OutlinedButton(
                  onPressed: () => _run(
                    () => ref.read(profileRepositoryProvider).unblockUser(profile.id),
                  ),
                  child: const Text('Unblock'),
                )
              else if (summary.relationshipStatus != ProfileRelationshipStatus.self)
                OutlinedButton(
                  onPressed: () => _run(
                    () => ref.read(profileRepositoryProvider).blockUser(profile.id),
                  ),
                  child: const Text('Block'),
                ),
              if (summary.relationshipStatus != ProfileRelationshipStatus.self)
                TextButton(
                  onPressed: () => showReportUserSheet(context, profile),
                  child: const Text('Report'),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Wire profile entry points**

In `ContactsScreen`, `GroupDetailSheet`, and chat member/avatar surfaces, navigate with:

```dart
context.push('/profile/${profile.id}');
```

Use `push` for sheets and detail pages so back navigation returns to the current workflow.

- [ ] **Step 6: Run UI tests**

Run:

```bash
rtk flutter test test/features/profile/user_profile_screen_test.dart test/shared/navigation/app_router_test.dart
```

Expected: PASS.

---

## Task 4: Privacy And Safety Settings

**Files:**
- Modify: `lib/features/settings/settings_repository.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/settings/settings_repository_test.dart`
- Test: `test/features/settings/settings_screen_test.dart`

- [ ] **Step 1: Add repository tests**

Add to `test/features/settings/settings_repository_test.dart`:

```dart
test('listBlockedUsers calls scoped blocks query', () async {
  final dataSource = FakeSettingsDataSource()
    ..blockedRows = [
      {
        'blocked': {
          'id': 'user-2',
          'username': 'ada',
          'display_name': 'Ada',
          'alias': null,
          'avatar_url': null,
          'bio': '',
          'created_at': '2026-05-18T00:00:00Z',
          'updated_at': '2026-05-18T00:00:00Z',
        },
      },
    ];
  final repository = SettingsRepository.withDataSource(dataSource);

  final users = await repository.listBlockedUsers();

  expect(users.single.username, 'ada');
});
```

- [ ] **Step 2: Add repository APIs**

Extend `SettingsRepository` with:

```dart
Future<List<Profile>> listBlockedUsers();
Future<void> unblockUser(String userId);
```

Implement Supabase data source query:

```dart
final rows = await _client
    .from('blocks')
    .select('blocked:profiles!blocks_blocked_id_fkey(*)')
    .eq('blocker_id', currentUserId)
    .order('created_at');
```

Parse:

```dart
return rows
    .map((row) => Profile.fromJson(row['blocked'] as Map<String, dynamic>))
    .toList(growable: false);
```

For unblock, call `unblock_user`.

- [ ] **Step 3: Add Settings UI section**

In `SettingsScreen`, add a `Privacy & Safety` section below profile editing:

```dart
ListTile(
  leading: const Icon(Icons.shield_outlined),
  title: const Text('Blocked users'),
  subtitle: const Text('Manage people you have blocked'),
  onTap: () => showBlockedUsersSheet(context, ref),
)
```

Implement `showBlockedUsersSheet` as a focused bottom sheet in the same file unless it grows beyond 120 lines; if it grows, split to `blocked_users_sheet.dart`.

- [ ] **Step 4: Add settings screen tests**

Add test:

```dart
testWidgets('settings opens blocked users sheet', (tester) async {
  await tester.pumpWidget(buildSettingsHarness(blockedUsers: [adaProfile]));

  await tester.tap(find.text('Blocked users'));
  await tester.pumpAndSettle();

  expect(find.text('Ada'), findsOneWidget);
  expect(find.text('Unblock'), findsOneWidget);
});
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
rtk flutter test test/features/settings/settings_repository_test.dart test/features/settings/settings_screen_test.dart
```

Expected: PASS.

---

## Task 5: Report User Sheet

**Files:**
- Create: `lib/features/profile/report_user_sheet.dart`
- Test: `test/features/profile/report_user_sheet_test.dart`

- [ ] **Step 1: Add sheet tests**

Create `test/features/profile/report_user_sheet_test.dart`:

```dart
testWidgets('report sheet submits selected reason and details', (tester) async {
  final repository = FakeProfileRepository();
  await tester.pumpWidget(buildReportHarness(repository: repository));

  await tester.tap(find.text('Spam'));
  await tester.enterText(find.byType(TextField), 'Repeated spam invites');
  await tester.tap(find.text('Submit report'));
  await tester.pumpAndSettle();

  expect(repository.reportedReason, ReportReason.spam);
  expect(repository.reportedDetails, 'Repeated spam invites');
});
```

- [ ] **Step 2: Implement report sheet**

Create `lib/features/profile/report_user_sheet.dart` with:

```dart
Future<void> showReportUserSheet(BuildContext context, Profile profile) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ReportUserSheet(profile: profile),
  );
}
```

The sheet must:

- default to `ReportReason.spam`
- show all `ReportReason.values`
- cap details at 1000 characters with `maxLength: 1000`
- call `ProfileRepository.reportUser`
- show `Could not submit report. Try again.` on failure
- close on success

- [ ] **Step 3: Run tests**

Run:

```bash
rtk flutter test test/features/profile/report_user_sheet_test.dart
```

Expected: PASS.

---

## Task 6: Circles Starter Shell

**Files:**
- Create: `lib/features/circles/circles_repository.dart`
- Modify: `lib/features/circles/circles_screen.dart`
- Test: `test/features/circles/circles_screen_test.dart`

- [ ] **Step 1: Add starter UI tests**

Create `test/features/circles/circles_screen_test.dart`:

```dart
testWidgets('circles starter shell shows creation entry point', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: CirclesScreen()));

  expect(find.text('Circles'), findsOneWidget);
  expect(find.text('Private spaces for familiar groups'), findsOneWidget);
  expect(find.text('Create Circle'), findsOneWidget);
});

testWidgets('create circle entry explains upcoming channels', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: CirclesScreen()));

  await tester.tap(find.text('Create Circle'));
  await tester.pumpAndSettle();

  expect(find.text('Circle creation is coming next'), findsOneWidget);
  expect(find.text('Text channels, announcements, and invited members will live here.'), findsOneWidget);
});
```

- [ ] **Step 2: Implement repository boundary**

Create `lib/features/circles/circles_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final circlesRepositoryProvider = Provider<CirclesRepository>((ref) {
  return const CirclesRepository();
});

class CirclesRepository {
  const CirclesRepository();

  Future<List<CircleSummary>> listCircles() async {
    return const [];
  }
}

class CircleSummary {
  const CircleSummary({
    required this.id,
    required this.name,
    required this.memberCount,
  });

  final String id;
  final String name;
  final int memberCount;
}
```

- [ ] **Step 3: Replace empty Circles screen**

Modify `lib/features/circles/circles_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circles_repository.dart';

class CirclesScreen extends ConsumerWidget {
  const CirclesScreen({super.key});

  static const path = '/circles';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Circles')),
      body: FutureBuilder<List<CircleSummary>>(
        future: ref.watch(circlesRepositoryProvider).listCircles(),
        builder: (context, snapshot) {
          final circles = snapshot.data ?? const <CircleSummary>[];
          if (circles.isEmpty) {
            return _EmptyCircles(
              onCreate: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Circle creation is coming next'),
                  content: const Text(
                    'Text channels, announcements, and invited members will live here.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final circle in circles)
                ListTile(
                  title: Text(circle.name),
                  subtitle: Text('${circle.memberCount} members'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyCircles extends StatelessWidget {
  const _EmptyCircles({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_2_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'Private spaces for familiar groups',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Start with invite-only circles, then add channels and announcements.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onCreate,
                child: const Text('Create Circle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run circles tests**

Run:

```bash
rtk flutter test test/features/circles/circles_screen_test.dart
```

Expected: PASS.

---

## Task 7: End-To-End Integration And Remote Migration

**Files:**
- Modify docs if behavior changes materially: `README.md`
- Modify docs if roadmap changes: `docs/superpowers/specs/2026-05-17-wecord-design.md`

- [ ] **Step 1: Run focused feature tests**

Run:

```bash
rtk flutter test \
  test/supabase/private_chat_schema_test.dart \
  test/shared/models/private_chat_models_test.dart \
  test/features/profile \
  test/features/settings \
  test/features/circles
```

Expected: PASS.

- [ ] **Step 2: Run full static analysis**

Run:

```bash
rtk flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run:

```bash
rtk flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Push migration to Supabase**

Run:

```bash
rtk supabase migration list
rtk supabase db push --yes
rtk supabase migration list
```

Expected: `202605190001` appears as local before push and local/remote after push.

- [ ] **Step 5: Validate remote RPC bodies**

Run:

```bash
rtk supabase db query --linked "select proname, pg_get_functiondef(p.oid) as body from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and proname in ('block_user', 'unblock_user', 'report_user', 'get_profile_summary', 'are_users_blocked') order by proname;"
```

Expected: query returns all five functions and `block_user`, `report_user`, and `get_profile_summary` mention `auth.uid()`.

- [ ] **Step 6: Manual QA checklist**

Run the app on web/iOS/macOS and verify:

- Open a friend profile from Contacts.
- Open a member profile from group detail.
- Start a direct chat from a friend profile.
- Send friend request from a non-friend profile.
- Block a user, then confirm friend request/direct chat actions disappear.
- Unblock from profile and from Settings block list.
- Submit a report and see the sheet close.
- Open Circles tab and see starter shell/create placeholder.

- [ ] **Step 7: Commit and push**

Stage the milestone files, including the pre-existing Podfile.lock changes if they are still dirty and match current dependency state:

```bash
rtk git status --short
rtk git add -A
rtk git commit -m "Add identity and safety foundation"
rtk git push -u origin wecord-foundation
```

Expected: branch pushed to GitHub.

---

## Subagent Execution Split

Use `superpowers:subagent-driven-development` during implementation.

- Worker 1 owns Task 1 backend SQL and schema tests.
- Worker 2 owns Task 2 domain models and repository tests.
- Worker 3 owns Task 3 profile screen/navigation and entry points.
- Worker 4 owns Task 4 settings privacy/block list.
- Worker 5 owns Task 5 report sheet.
- Worker 6 owns Task 6 circles starter shell.
- Main agent owns integration, remote migration, final verification, and commit/push.

Workers are not alone in the codebase. Each worker must avoid reverting edits made by others and must list changed files in their final report.

## Self-Review

- Spec coverage: profile pages, block/unblock/report, privacy settings, and Circles starter shell each map to a task.
- Placeholder scan: no TODO/TBD placeholders; Circles channel creation is explicitly out of scope and represented as a starter placeholder.
- Type consistency: `ProfileSummary`, `ProfileRelationshipStatus`, `ReportReason`, and repository method names are defined before use.
- Scope check: full Circles implementation is intentionally excluded so this remains one milestone.
