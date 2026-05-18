# WeCord Notifications MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local notification behavior for unread incoming messages while the signed-in app shell is active.

**Architecture:** Extend conversation summaries with latest sender metadata, then build a notification module around local preferences, a platform notification service boundary, and a coordinator mounted inside the signed-in shell. Keep full APNs/FCM/Web Push out of scope while preserving a service interface that can support them later.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase Realtime/Postgres, `flutter_local_notifications`, `shared_preferences`, Flutter widget/unit tests.

---

## File Structure

- Create `supabase/migrations/202605180007_notifications_mvp.sql`: replace `list_conversation_summaries()` to include `last_message_sender_id`.
- Modify `lib/shared/models/conversation.dart`: add nullable `lastMessageSenderId`.
- Modify `test/shared/models/private_chat_models_test.dart`: cover parsing/copying sender id.
- Modify `test/supabase/private_chat_schema_test.dart`: assert summary sender id exists.
- Create `lib/features/notifications/notification_preferences_repository.dart`: local preferences abstraction.
- Create `lib/features/notifications/local_notification_service.dart`: permission/show/tap platform boundary.
- Create `lib/features/notifications/notification_coordinator.dart`: notification decision engine.
- Create `lib/features/notifications/notification_shell_listener.dart`: shell-mounted listener widget.
- Modify `lib/features/shell/wecord_shell.dart`: mount notification listener around shell child.
- Modify `lib/features/settings/settings_screen.dart`: add notification controls.
- Modify `pubspec.yaml` and `pubspec.lock`: add `flutter_local_notifications` and `shared_preferences`.
- Create tests under `test/features/notifications`.
- Modify affected chat/settings/shell tests for new providers and summary fields.

## Task 1: Conversation Summary Sender Metadata

**Files:**
- Create: `supabase/migrations/202605180007_notifications_mvp.sql`
- Modify: `lib/shared/models/conversation.dart`
- Modify: `test/shared/models/private_chat_models_test.dart`
- Modify: `test/supabase/private_chat_schema_test.dart`
- Modify: affected `ConversationSummary` test fixtures.

- [ ] **Step 1: Write failing schema test**

Add to `test/supabase/private_chat_schema_test.dart`:

```dart
test('conversation summaries include latest message sender for notifications', () {
  final sql = allMigrationSql();
  final summariesBody = functionBody(sql, 'list_conversation_summaries');

  expect(summariesBody, contains('last_message_sender_id'));
  expect(summariesBody, contains('lm.sender_id as last_message_sender_id'));
});
```

- [ ] **Step 2: Write failing model test**

Add to `test/shared/models/private_chat_models_test.dart`:

```dart
test('Conversation parses latest message sender id', () {
  final conversation = ConversationSummary.fromJson({
    'id': 'conversation-1',
    'type': 'direct',
    'title': 'Ada',
    'avatar_url': null,
    'last_message_body': 'Hi',
    'last_message_sender_id': 'user-2',
    'last_message_at': '2026-05-18T00:00:00.000Z',
    'unread_count': 1,
  });

  expect(conversation.lastMessageSenderId, 'user-2');
  expect(
    conversation.copyWith(lastMessageSenderId: null).lastMessageSenderId,
    isNull,
  );
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
rtk flutter test test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
```

Expected: failures for missing `lastMessageSenderId` and missing SQL field.

- [ ] **Step 4: Add migration**

Create `supabase/migrations/202605180007_notifications_mvp.sql` by copying the current redacted `list_conversation_summaries()` function shape from `202605180006_social_chat_v2_fixes.sql`, preserving redaction and unread logic, and adding:

```sql
last_message_sender_id uuid
```

to the returned table plus:

```sql
lm.sender_id as last_message_sender_id,
```

to the select list.

- [ ] **Step 5: Update model**

In `lib/shared/models/conversation.dart`, add:

```dart
this.lastMessageSenderId,
```

to the constructor, parse:

```dart
lastMessageSenderId: json['last_message_sender_id'] as String?,
```

add:

```dart
final String? lastMessageSenderId;
```

and support `lastMessageSenderId` in `copyWith`.

- [ ] **Step 6: Update fixtures**

Update existing `ConversationSummary.fromJson` maps with `last_message_sender_id` and keep constructor fixtures concise by relying on the nullable constructor default.

- [ ] **Step 7: Verify and commit**

Run:

```bash
rtk dart format lib/shared/models/conversation.dart test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
rtk flutter test test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add supabase/migrations/202605180007_notifications_mvp.sql lib/shared/models/conversation.dart test/shared/models/private_chat_models_test.dart test/supabase/private_chat_schema_test.dart
rtk git commit -m "feat: add notification summary metadata"
```

## Task 2: Notification Preferences And Local Service

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/features/notifications/notification_preferences_repository.dart`
- Create: `lib/features/notifications/local_notification_service.dart`
- Create: `test/features/notifications/notification_preferences_repository_test.dart`
- Create: `test/features/notifications/local_notification_service_test.dart`

- [ ] **Step 1: Add dependencies**

Run:

```bash
rtk flutter pub add flutter_local_notifications shared_preferences
```

Expected: `pubspec.yaml` and `pubspec.lock` update.

- [ ] **Step 2: Write preferences tests**

Create `test/features/notifications/notification_preferences_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';

void main() {
  test('notification preferences default to enabled with previews', () async {
    final store = InMemoryNotificationPreferencesStore();
    final repository = NotificationPreferencesRepository.withStore(store);

    final preferences = await repository.load();

    expect(preferences.enabled, isTrue);
    expect(preferences.showPreviews, isTrue);
  });

  test('notification preferences persist updates', () async {
    final store = InMemoryNotificationPreferencesStore();
    final repository = NotificationPreferencesRepository.withStore(store);

    await repository.save(
      const NotificationPreferences(enabled: false, showPreviews: false),
    );

    final preferences = await repository.load();
    expect(preferences.enabled, isFalse);
    expect(preferences.showPreviews, isFalse);
  });
}
```

- [ ] **Step 3: Write service tests**

Create `test/features/notifications/local_notification_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';

void main() {
  test('fake notification service records shown message notifications', () async {
    final service = FakeLocalNotificationService();

    await service.showMessageNotification(
      conversationId: 'conversation-1',
      title: 'Ada',
      body: 'Hi',
    );

    expect(service.shownNotifications.single.title, 'Ada');
    expect(service.shownNotifications.single.body, 'Hi');
    expect(service.shownNotifications.single.payload, 'conversation-1');
  });

  test('fake notification service exposes permission status', () async {
    final service = FakeLocalNotificationService(
      status: NotificationPermissionStatus.denied,
    );

    expect(await service.permissionStatus(), NotificationPermissionStatus.denied);
  });
}
```

- [ ] **Step 4: Run tests and verify failure**

Run:

```bash
rtk flutter test test/features/notifications/notification_preferences_repository_test.dart test/features/notifications/local_notification_service_test.dart
```

Expected: failures because notification classes do not exist.

- [ ] **Step 5: Implement preferences repository**

Create `lib/features/notifications/notification_preferences_repository.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((ref) {
  return NotificationPreferencesRepository.withStore(
    SharedPreferencesNotificationPreferencesStore(),
  );
});

class NotificationPreferences {
  const NotificationPreferences({
    required this.enabled,
    required this.showPreviews,
  });

  final bool enabled;
  final bool showPreviews;

  NotificationPreferences copyWith({bool? enabled, bool? showPreviews}) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      showPreviews: showPreviews ?? this.showPreviews,
    );
  }
}
```

Add `NotificationPreferencesStore`, `SharedPreferencesNotificationPreferencesStore`, `InMemoryNotificationPreferencesStore`, and `NotificationPreferencesRepository` with `load()` and `save()` methods. Use keys:

```dart
wecord.notifications.enabled
wecord.notifications.show_previews
```

- [ ] **Step 6: Implement local service boundary**

Create `lib/features/notifications/local_notification_service.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localNotificationServiceProvider = Provider<LocalNotificationService>((ref) {
  if (kIsWeb) {
    return FakeLocalNotificationService();
  }
  return FlutterLocalNotificationService();
});
```

Define:

```dart
enum NotificationPermissionStatus { notRequested, granted, denied, unavailable }

abstract interface class LocalNotificationService {
  Future<NotificationPermissionStatus> permissionStatus();
  Future<NotificationPermissionStatus> requestPermission();
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  });
  Stream<String> notificationTaps();
}
```

Implement `FlutterLocalNotificationService` with `FlutterLocalNotificationsPlugin`, Darwin initialization, macOS/iOS permission requests, and notification payload set to `conversationId`. Implement `FakeLocalNotificationService` for tests.

- [ ] **Step 7: Verify and commit**

Run:

```bash
rtk dart format lib/features/notifications/notification_preferences_repository.dart lib/features/notifications/local_notification_service.dart test/features/notifications/notification_preferences_repository_test.dart test/features/notifications/local_notification_service_test.dart
rtk flutter test test/features/notifications/notification_preferences_repository_test.dart test/features/notifications/local_notification_service_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add pubspec.yaml pubspec.lock lib/features/notifications/notification_preferences_repository.dart lib/features/notifications/local_notification_service.dart test/features/notifications/notification_preferences_repository_test.dart test/features/notifications/local_notification_service_test.dart
rtk git commit -m "feat: add local notification services"
```

## Task 3: Notification Coordinator

**Files:**
- Create: `lib/features/notifications/notification_coordinator.dart`
- Create: `test/features/notifications/notification_coordinator_test.dart`
- Modify: existing fake repositories that implement `ChatsRepository` when analyzer requires notification summary fixtures.

- [ ] **Step 1: Write coordinator tests**

Create `test/features/notifications/notification_coordinator_test.dart` with tests for:

```dart
test('does not notify on initial snapshot', () async {
  final harness = NotificationCoordinatorHarness();
  harness.seed([harness.summary(id: 'c1', unreadCount: 1)]);

  await harness.start();

  expect(harness.notifications, isEmpty);
});

test('notifies when a conversation gains a newer unread incoming message', () async {
  final harness = NotificationCoordinatorHarness();
  harness.seed([harness.summary(id: 'c1')]);
  await harness.start();

  await harness.emit([harness.summary(id: 'c1', unreadCount: 1, body: 'hello')]);

  expect(harness.notifications.single.body, 'hello');
});

test('does not notify for the active conversation', () async {
  final harness = NotificationCoordinatorHarness(activeConversationId: 'c1');
  harness.seed([harness.summary(id: 'c1')]);
  await harness.start();

  await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);

  expect(harness.notifications, isEmpty);
});

test('does not notify when notifications are disabled', () async {
  final harness = NotificationCoordinatorHarness(notificationsEnabled: false);
  harness.seed([harness.summary(id: 'c1')]);
  await harness.start();

  await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);

  expect(harness.notifications, isEmpty);
});

test('uses New message when previews are disabled', () async {
  final harness = NotificationCoordinatorHarness(previewsEnabled: false);
  harness.seed([harness.summary(id: 'c1')]);
  await harness.start();

  await harness.emit([harness.summary(id: 'c1', unreadCount: 1, body: 'secret')]);

  expect(harness.notifications.single.body, 'New message');
});

test('does not notify for messages from the current user', () async {
  final harness = NotificationCoordinatorHarness(currentUserId: 'me');
  harness.seed([harness.summary(id: 'c1')]);
  await harness.start();

  await harness.emit([
    harness.summary(id: 'c1', unreadCount: 1, lastMessageSenderId: 'me'),
  ]);

  expect(harness.notifications, isEmpty);
});
```

Use fake dependencies:
- fake chats repository with `listConversations()` and controllable `conversationChanges()`.
- fake auth user id.
- `InMemoryNotificationPreferencesStore`.
- `FakeLocalNotificationService`.
- active conversation id provider or callback.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
rtk flutter test test/features/notifications/notification_coordinator_test.dart
```

Expected: failure because coordinator does not exist.

- [ ] **Step 3: Implement coordinator**

Create `lib/features/notifications/notification_coordinator.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
```

Add:

```dart
final activeConversationIdProvider = StateProvider<String?>((ref) => null);

final notificationCoordinatorProvider = Provider<NotificationCoordinator>((ref) {
  return NotificationCoordinator(
    authRepository: ref.watch(authRepositoryProvider),
    chatsRepository: ref.watch(chatsRepositoryProvider),
    preferencesRepository: ref.watch(notificationPreferencesRepositoryProvider),
    notificationService: ref.watch(localNotificationServiceProvider),
    activeConversationId: () => ref.read(activeConversationIdProvider),
  );
});
```

Coordinator behavior:
- `start()` loads initial conversations into `_previousById` without notifying.
- subscribes to `conversationChanges()`.
- on change, reloads conversations and compares previous vs next.
- notify only when:
  - preferences enabled,
  - `conversation.id != activeConversationId`,
  - `conversation.unreadCount > 0`,
  - `conversation.lastMessageAt != null`,
  - latest message is newer than previous same conversation latest,
  - `conversation.lastMessageSenderId != currentUser.id`.
- body is `conversation.lastMessageBody` when previews enabled and non-empty; otherwise `New message`.
- title is `conversation.title` if non-empty; otherwise `Conversation`.
- catches repository/service errors.

- [ ] **Step 4: Verify and commit**

Run:

```bash
rtk dart format lib/features/notifications/notification_coordinator.dart test/features/notifications/notification_coordinator_test.dart
rtk flutter test test/features/notifications/notification_coordinator_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add lib/features/notifications/notification_coordinator.dart test/features/notifications/notification_coordinator_test.dart
rtk git commit -m "feat: add notification coordinator"
```

## Task 4: Shell And Settings Integration

**Files:**
- Create: `lib/features/notifications/notification_shell_listener.dart`
- Modify: `lib/features/shell/wecord_shell.dart`
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Create or modify: `test/features/notifications/notification_shell_listener_test.dart`
- Modify: `test/features/settings/settings_screen_test.dart`
- Modify: `test/features/shell/wecord_shell_test.dart`

- [ ] **Step 1: Write shell/settings tests**

Add tests:

```dart
testWidgets('settings renders notification controls', (tester) async {
  await pumpSettings(tester);

  expect(find.text('Notifications'), findsOneWidget);
  expect(find.text('Message previews'), findsOneWidget);
});

testWidgets('settings toggles notification preferences', (tester) async {
  final store = InMemoryNotificationPreferencesStore();
  await pumpSettings(tester, preferencesStore: store);

  await tester.tap(find.byType(SwitchListTile).first);
  await tester.pump();

  expect((await store.load()).enabled, isFalse);
});

testWidgets('notification shell listener starts the coordinator', (tester) async {
  final coordinator = RecordingNotificationCoordinator();

  await tester.pumpWidget(NotificationShellListenerTestApp(coordinator));

  expect(coordinator.startCount, 1);
});

testWidgets('chat thread marks the active conversation while mounted', (tester) async {
  final container = ProviderContainer();

  await pumpChatThread(tester, container: container, conversationId: 'c1');
  expect(container.read(activeConversationIdProvider), 'c1');

  await tester.pumpWidget(const SizedBox.shrink());
  expect(container.read(activeConversationIdProvider), isNull);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
rtk flutter test test/features/settings/settings_screen_test.dart test/features/notifications/notification_shell_listener_test.dart test/features/chats/chat_thread_screen_test.dart test/features/shell/wecord_shell_test.dart
```

Expected: failures because UI/listener integration is missing.

- [ ] **Step 3: Add notification shell listener**

Create `lib/features/notifications/notification_shell_listener.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';

class NotificationShellListener extends ConsumerStatefulWidget {
  const NotificationShellListener({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<NotificationShellListener> createState() =>
      _NotificationShellListenerState();
}
```

In `initState`, start coordinator after first frame and listen to `localNotificationServiceProvider.notificationTaps()` to navigate to `${ChatsScreen.path}/$conversationId`.

- [ ] **Step 4: Mount listener in shell**

Modify `WeCordShell` to wrap its `child` in `NotificationShellListener`. Preserve current navigation rail/bar behavior.

- [ ] **Step 5: Track active conversation**

In `ChatThreadScreen`, set `activeConversationIdProvider` to `widget.conversationId` while mounted and clear it on dispose only if it still matches.

- [ ] **Step 6: Add Settings controls**

In `SettingsScreen`, add a Notifications section with:
- SwitchListTile title `Notifications`
- SwitchListTile title `Message previews`
- permission status text
- OutlinedButton text `Request permission`

Read/write through `notificationPreferencesRepositoryProvider` and `localNotificationServiceProvider`.

- [ ] **Step 7: Verify and commit**

Run:

```bash
rtk dart format lib/features/notifications/notification_shell_listener.dart lib/features/shell/wecord_shell.dart lib/features/chats/chat_thread_screen.dart lib/features/settings/settings_screen.dart test/features/notifications/notification_shell_listener_test.dart test/features/settings/settings_screen_test.dart test/features/chats/chat_thread_screen_test.dart test/features/shell/wecord_shell_test.dart
rtk flutter test test/features/settings/settings_screen_test.dart test/features/notifications/notification_shell_listener_test.dart test/features/chats/chat_thread_screen_test.dart test/features/shell/wecord_shell_test.dart
rtk flutter analyze
```

Commit:

```bash
rtk git add lib/features/notifications/notification_shell_listener.dart lib/features/shell/wecord_shell.dart lib/features/chats/chat_thread_screen.dart lib/features/settings/settings_screen.dart test/features/notifications/notification_shell_listener_test.dart test/features/settings/settings_screen_test.dart test/features/chats/chat_thread_screen_test.dart test/features/shell/wecord_shell_test.dart
rtk git commit -m "feat: wire notifications into shell and settings"
```

## Task 5: Final Verification And Push

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README**

Update `README.md` current status to mention local notification MVP and notification settings.

- [ ] **Step 2: Run full verification**

Run:

```bash
rtk dart format lib test
rtk flutter analyze
rtk flutter test
```

Expected:
- analyze reports no issues.
- all tests pass.

- [ ] **Step 3: Push Supabase migration**

Run:

```bash
rtk supabase db push
```

Expected: Supabase prompts for `202605180007_notifications_mvp.sql`; answer `y`.

- [ ] **Step 4: Commit and push**

Run:

```bash
rtk git add README.md
rtk git commit -m "docs: update notifications milestone"
rtk git push
```

## Self-Review

Spec coverage:
- Local notification behavior is covered by Tasks 2, 3, and 4.
- Notification rules are covered by Task 3 coordinator tests.
- Settings controls are covered by Task 4.
- Summary sender metadata needed to avoid self-notifications is covered by Task 1.
- Full remote push is explicitly excluded.

Placeholder scan:
- The plan contains no placeholder markers or unspecified test steps.
- Each task lists exact files, commands, expected outcomes, and commit commands.

Type consistency:
- `NotificationPreferences`, `NotificationPermissionStatus`, `LocalNotificationService`, `NotificationCoordinator`, `activeConversationIdProvider`, and `NotificationShellListener` are introduced before they are used by later tasks.
