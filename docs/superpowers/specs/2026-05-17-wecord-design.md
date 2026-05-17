# WeCord MVP Design

## Summary

WeCord is a familiar-social real-time chat app that combines a WeChat-like primary experience with a Discord-like community layer. The first version is "WeChat first": users open the app into a recent chat list, continue private chats and group chats quickly, and can enter small familiar communities through a secondary tab.

The product starts with route A, the lightweight WeChat-style MVP, while keeping clear extension points for route B, familiar social circles, and route C, private intimate spaces.

## Goals

- Ship a usable real-time chat MVP across iOS, macOS, and Web.
- Make private chat and group chat feel fast, reliable, and familiar.
- Add a lightweight community/channel model without making it the main navigation.
- Keep the data model ready for future social feed, shared albums, private spaces, and voice channels.
- Avoid heavy features such as full Discord-style public servers, voice rooms, video calls, and AI summaries in the first build.

## Non-Goals

- Public community discovery.
- Open server marketplace.
- End-to-end encryption.
- Full voice/video calling.
- Payment, mini programs, or marketplace features.
- Large-scale moderation tooling beyond basic blocking and reporting.

## Target Platforms

- iOS app.
- macOS desktop app.
- Web app.

The first implementation should prioritize shared code and a consistent interaction model. Platform-specific polish can be added after the core message loop is stable.

## Recommended Stack

### Client

Use Flutter for iOS, macOS, and Web. Flutter gives WeCord one shared client codebase and officially supports the target platforms. The app should keep platform-specific code small and isolated behind services such as notifications, file picking, and local storage.

### Backend

Use Supabase:

- Supabase Auth for accounts and sessions.
- Postgres for relational chat data.
- Supabase Realtime for messages, typing indicators, online presence, read receipts, and lightweight activity events.
- Supabase Storage for avatars, images, files, and voice message files.
- Row Level Security for membership-based access control.
- Edge Functions for server-side workflows such as friend requests, group invites, notification fan-out, and future AI features.

### Future Voice Layer

Reserve LiveKit as the future voice/video layer. The MVP should not implement voice channels, but the data model should leave room for channel types and real-time room metadata.

## Product Shape

### Primary Navigation

Use a WeChat-first structure:

- Chats: default home screen with recent private chats, group chats, and followed channel conversations.
- Contacts: friends, friend requests, groups, and familiar circles.
- Circles: small private communities with channels.
- Me: profile, settings, privacy, devices, and notification controls.

On desktop and larger web screens, use a sidebar layout:

- Left column: main navigation.
- Middle column: chat list or contacts/circles list.
- Right panel: active conversation.

On iPhone-sized screens, use bottom tabs and full-screen navigation.

### MVP Features

#### Account

- Email login for the first version.
- Profile with avatar, display name, username, and short bio.
- Basic account settings.

Phone login and Apple login can be added after the first stable build.

#### Friends

- Search by username.
- Send and accept friend requests.
- Friend list.
- Friend remarks.
- Block user.

#### Conversations

- Recent chat list.
- Private conversations.
- Group conversations.
- Pinned conversations.
- Mute per conversation.
- Unread count.
- Last message preview.

#### Messaging

- Text messages.
- Image messages.
- File attachment metadata.
- Reply to message.
- Edit message within a limited window.
- Recall/delete own message within a limited window.
- Typing indicator.
- Online presence.
- Read receipts for private chats.
- Delivered/read state suitable for group chat later, but group read receipts can start simpler.

#### Groups

- Create group from friends.
- Group name and avatar.
- Invite friends.
- Leave group.
- Group owner and admins.
- Group announcement.
- Mention a member with `@`.

#### Circles

Circles are familiar communities, not public Discord servers. A circle can represent a friend group, class, family, club, or project team.

MVP circle features:

- Create a private circle.
- Invite friends.
- Basic member list.
- Text channels inside a circle.
- Announcement channel type.
- Channel mute/follow setting.

Circles should appear as a secondary tab. Important followed channel activity can appear in the main chat list, but channels should not overwhelm private chats.

#### Search

- Search friends.
- Search groups.
- Search recent conversations.
- Search message text in the current conversation.

Global historical search can be optimized later.

#### Notifications

- In-app unread indicators.
- Per-conversation mute.
- Per-channel mute/follow.
- Push notifications as a second implementation phase after the core chat loop works.

#### Privacy and Safety

- Block list.
- Friend request privacy.
- Online status visibility setting.
- Basic report action.
- Membership-based access control through database policies.

## Future Extension Points

### Route B: Familiar Social Circles

Add after the chat MVP is stable:

- Friend status.
- Timeline/feed.
- Shared moments for close friends.
- Mutual friends.
- School/company/local familiar circles.

The data model should support user-generated posts and audience visibility, but no feed UI is needed in the MVP.

### Route C: Private Intimate Spaces

Add after core groups and circles are stable:

- Family/friend/couple spaces.
- Shared album.
- Shared calendar.
- Private channels.
- Disappearing messages.
- Memory timeline.

The MVP should keep circles private and invite-only so this path remains natural.

### Voice and Video

Add with LiveKit later:

- Voice channel inside a circle.
- Private voice call.
- Small group voice call.
- Optional screen sharing on desktop/web.

The MVP data model should include a generic `channel_type` field so text, announcement, and future voice channels can coexist.

## Data Model

Use UUID primary keys and timestamp columns for all core tables. Use soft-delete where message history or audit behavior matters.

Core tables:

- `profiles`: public user profile data linked to auth users.
- `friend_requests`: requester, receiver, status, timestamps.
- `friendships`: two user ids, status, remark fields.
- `conversations`: private, group, or channel-backed conversation.
- `conversation_members`: membership, role, mute, pinned, last_read_message_id.
- `messages`: conversation id, sender, type, body, attachment metadata, reply target, edit state, recall state.
- `message_reads`: per-user read state when needed beyond `last_read_message_id`.
- `groups`: group metadata for group conversations.
- `group_members`: group membership and role.
- `circles`: private familiar communities.
- `circle_members`: circle membership and role.
- `channels`: circle channels with type, name, position, and notification defaults.
- `attachments`: storage object metadata for uploaded files.
- `blocks`: blocker, blocked user, reason, timestamps.
- `reports`: reporter, target type, target id, reason, status.

Design note: private chats, groups, and channels should all map to `conversations`. This keeps the message UI and real-time subscription model consistent.

## Realtime Events

Use Supabase Realtime channels scoped by conversation and user membership.

Events:

- `message.inserted`: new message in a conversation.
- `message.updated`: edited or recalled message.
- `typing.started` / `typing.stopped`: ephemeral typing state.
- `presence.updated`: online or active status.
- `read.updated`: latest read marker changed.
- `conversation.updated`: pinned, muted, last message, or membership metadata changed.

Persist durable state in Postgres. Use ephemeral realtime events for typing and presence. The client should reconcile realtime events with database fetches so reconnects recover cleanly.

## Permissions

All chat data must be protected by membership checks:

- A user can read a conversation only if they are a current member.
- A user can insert messages only into conversations they belong to and are allowed to write in.
- A user can read circle channels only if they are a member of that circle.
- A user can manage a group or circle only if their role allows it.
- A blocked user cannot create new direct interactions with the blocker.

RLS policies should be part of the implementation from the start, not deferred.

## Client Architecture

Suggested Flutter structure:

- `features/auth`
- `features/chats`
- `features/contacts`
- `features/circles`
- `features/settings`
- `shared/api`
- `shared/realtime`
- `shared/models`
- `shared/theme`
- `shared/widgets`

Keep Supabase calls behind repository/service classes. UI screens should depend on typed models and state providers, not raw database payloads.

Suggested client state:

- Auth/session provider.
- Conversation list provider.
- Active conversation provider.
- Presence provider.
- Upload provider.
- Settings/preferences provider.

## Error Handling

- Show optimistic messages with sending, sent, failed states.
- Allow retry for failed sends and uploads.
- On reconnect, refetch active conversation and recent chat list.
- Use clear empty states for no friends, no chats, and no circle channels.
- Prevent duplicate message display by using server-generated message ids and client-side temporary ids.

## Testing

Initial testing should cover:

- Auth flow.
- Friend request create/accept/reject.
- Conversation membership permissions.
- Sending and receiving messages.
- Message edit/recall permissions.
- Group creation and invitation.
- Circle channel membership access.
- Realtime reconnect reconciliation.

Database policies need dedicated tests or repeatable SQL verification scripts because permission bugs are high risk in chat products.

## Milestones

### Milestone 1: Foundation

- Create Flutter app for iOS, macOS, and Web.
- Configure Supabase project locally or remotely.
- Add auth, profiles, theme, navigation, and base layout.

### Milestone 2: Private Chat

- Friends and friend requests.
- Direct conversation creation.
- Text message send/receive.
- Chat list with unread state.
- Basic realtime subscription.

### Milestone 3: Group Chat

- Create group.
- Invite friends.
- Group chat messaging.
- Mentions and group announcement.

### Milestone 4: Circles and Channels

- Private circle creation.
- Circle membership.
- Text and announcement channels.
- Channel notification preferences.
- Followed channel activity in chat list.

### Milestone 5: Media and Polish

- Avatars.
- Image/file upload.
- Message reply/edit/recall.
- Search.
- Mute/pin settings.
- Presence and typing indicators.

### Milestone 6: Notifications and Release Readiness

- Push notification pipeline.
- Web notification support.
- Permission hardening.
- Cross-platform QA.
- Basic deployment documentation.

## MVP Defaults

- Use email/password auth first. Add magic link and Apple login later.
- Ship the first demo with in-app unread indicators. Add push notifications in Milestone 6.
- Treat Web as a real client, but prioritize iOS and macOS polish first.
- For group read receipts, show read counts first. Add individual read lists later if the UX needs it.

## References

- Flutter supported platforms: https://docs.flutter.dev/reference/supported-platforms
- Supabase Realtime: https://supabase.com/docs/guides/realtime
- Supabase Broadcast: https://supabase.com/docs/guides/realtime/broadcast
- LiveKit SDK platforms: https://docs.livekit.io/transport/sdk-platforms
