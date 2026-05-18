# WeCord Notifications MVP Design

## Goal

Make WeCord feel responsive when new messages arrive outside the currently open conversation by adding local notifications, unread-aware notification rules, and simple notification preferences.

This milestone intentionally avoids full remote push delivery. The app must be running or background-capable for notifications to fire. The design keeps a clean path toward a future APNs/FCM/Web Push milestone without adding those platform credentials now.

## Scope

### Local Notifications

The client listens for conversation changes while the signed-in shell is active. When a new unread message arrives in a conversation that is not currently open, WeCord shows a local notification.

Notification title:
- Direct chat: conversation title or sender display name.
- Group chat: group title.

Notification body:
- Latest message preview from the redacted conversation summary.
- Recalled messages show `Message deleted`.
- Empty previews fall back to `New message`.

Notification tap behavior:
- Navigate to the related chat thread when the app can receive the tap payload.
- If the platform does not provide a tap payload in this MVP, the notification still opens the app and the user can use the chat list.

### Notification Rules

Do not notify when:
- The user is signed out.
- The conversation is already open.
- The latest message is from the current user.
- The conversation has no unread messages.
- Notifications are disabled in settings.

Notify when:
- A direct or group conversation receives unread messages from another member.
- The app is open on another tab/screen, such as Contacts or Settings.

### Settings

Settings adds a Notifications section with:
- `Notifications` toggle.
- `Message previews` toggle.
- A short status line showing whether local notification permission is granted, denied, or not requested.
- `Request permission` action when permission is available but not granted.

Preference behavior:
- Notifications default to enabled in app state.
- Message previews default to enabled.
- Preferences are stored locally with `shared_preferences`.
- If message previews are disabled, notification body is `New message`.

### Platform Behavior

Use `flutter_local_notifications` for local notifications on supported Flutter targets, with macOS as the first fully exercised desktop target.

For Web:
- Use an in-memory no-op implementation in this milestone.
- Do not import browser-specific libraries.
- Keep the service interface compatible with a future browser Notification API implementation.

For iOS:
- Add dependency and permission flow wiring.
- Full background remote push is outside this milestone.

## Non-Goals

- APNs, FCM, or Web Push server delivery.
- Supabase Edge Functions for notification fan-out.
- Notification tokens table.
- Mention-specific notifications.
- Per-conversation mute settings.
- Quiet hours.
- Notification center/history.
- Badge count integration with OS app icons.
- Browser system notifications.

## Architecture

Add a `features/notifications` module with four pieces:

- `NotificationPreferencesRepository`: local storage for notification toggles.
- `LocalNotificationService`: platform boundary for permission, showing notifications, and tap callbacks.
- `NotificationCoordinator`: listens to chat summaries and decides whether to notify.
- `NotificationShellListener`: a small widget mounted inside the signed-in app shell.

The coordinator consumes existing chat APIs instead of reading Supabase directly:
- `ChatsRepository.conversationChanges()`
- `ChatsRepository.listConversations()`
- `AuthRepository.currentUser`

Extend `ConversationSummary` with `lastMessageSenderId`. The Supabase `list_conversation_summaries()` RPC should return this value from the latest message. This lets the coordinator reliably skip notifications for messages sent by the current user, even when the conversation still has older unread messages.

The coordinator keeps a previous snapshot of conversation summaries. It notifies only when a conversation transitions into a newer unread state. This prevents showing notifications for all existing unread conversations on startup.

## Data Flow

1. User signs in and reaches the shell.
2. `NotificationShellListener` starts `NotificationCoordinator`.
3. Coordinator loads notification preferences and the current conversation snapshot.
4. On `conversationChanges`, coordinator reloads conversations.
5. It compares old and new summaries.
6. If a conversation has a newer unread message and passes rules, it calls `LocalNotificationService.showMessageNotification`.
7. If the user taps a notification and the platform returns the payload, the app navigates to `/chats/:conversationId`.

## Error Handling

- Permission denied: keep preferences enabled but show status `Permission denied`; do not throw.
- Notification service unavailable: coordinator swallows the service error and continues listening.
- Repository reload fails: coordinator ignores that event and waits for the next realtime event.
- Missing title/body: use `Conversation` and `New message`.

## Testing

Repository tests:
- Notification preferences default to enabled.
- Preferences can be toggled and persist in memory/local store abstraction.

Service tests:
- Permission status is surfaced.
- Show notification records title/body/payload in fake service.

Coordinator tests:
- No notification on initial snapshot.
- Notify on new unread conversation update.
- Do not notify for currently open conversation.
- Do not notify when notifications disabled.
- Use `New message` when previews disabled.
- Do not leak recalled text because summaries already provide `Message deleted`.

Widget tests:
- Settings shows notification toggles and permission status.
- Toggling settings calls preferences repository.
- Shell mounts the notification listener only after sign-in.

Verification:
- `rtk flutter analyze`
- `rtk flutter test`

## Future Extension

The future Push milestone can add:
- `notification_tokens` table.
- Device token registration.
- Supabase Edge Function fan-out on message insert.
- APNs/FCM/Web Push credentials.
- Per-conversation mute and mention preferences.

The MVP should leave the coordinator and service interfaces stable enough that remote push can reuse the same preference model and notification payload shape.
