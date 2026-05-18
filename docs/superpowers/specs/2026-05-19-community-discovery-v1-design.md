# Community & Discovery v1 Design

## Purpose

Community & Discovery v1 turns WeCord from a private/group chat app into a familiar-social product with small private communities, lightweight social posts, stronger group management, and better ways to find shared history.

The priority is to make Circles useful first. A Circle is a private familiar space for friends, family, classmates, clubs, or project groups. It contains members, channels, and a simple activity feed. Group management, search, and media surfaces support this community layer without becoming separate large products.

## Goals

- Let a signed-in user create a Circle and invite existing friends.
- Let Circle members browse Circle channels and chat in those channels using the existing chat thread experience.
- Let Circle members post text and image updates to a Circle feed, then like, comment, delete, or report posts.
- Add group announcements and clearer group role behavior.
- Add global discovery for contacts, groups, Circles, and channels.
- Add a media center for chat attachments so images, voice messages, and files are easier to revisit.

## Non-Goals

- Public servers or public Circle discovery.
- Paid roles, bots, complex moderation queues, or audit logs.
- Full Discord-style permission matrices.
- Infinite social feed algorithms.
- Remote push notification changes.
- Rich post editing, post sharing, or reposting.

## Product Shape

### Circles

Circles appear in the existing Circles tab. The empty state becomes a real creation entry point. The list shows Circle name, avatar, member count, channel count, and recent activity.

A Circle detail screen has two primary areas:

- Channels: text channels such as `general`, `photos`, and `plans`. Tapping a channel opens the existing chat thread route because channel conversations use the same message model as direct and group conversations.
- Feed: lightweight Circle posts for text/image updates. This is closer to WeChat Moments, but scoped to the Circle instead of all friends.

The first implementation should create one default `general` channel with each Circle. Additional channel creation can ship in the same milestone if the schema and UI are already in place, but the app must remain useful with only the default channel.

### Circle Roles

Roles stay simple:

- Owner: created the Circle, can rename, invite members, remove members, create channels, and delete the Circle later.
- Admin: can invite members, remove regular members, and create channels.
- Member: can read channels, send channel messages, post to feed, like, comment, and report.

Owner transfer is not required in v1, but the schema should not prevent it later.

### Circle Feed

Circle feed posts support:

- Text body.
- Optional image attachment using the same storage approach as image messages.
- Like/unlike.
- Comments.
- Delete own post.
- Report another user's post.

Feed visibility is Circle-member-only. Deleted posts disappear from the feed for normal users. Reported posts remain visible until later moderation tooling exists.

### Group Management

Group detail gains an announcement field. Owners/admins can edit it. Members can read it from group detail and see a compact announcement strip near the top of the group chat when one exists.

Existing group admin actions stay aligned with current group membership:

- Owner/admin can invite friends.
- Owner/admin can remove regular members.
- Members can leave.
- Owners cannot remove themselves through the remove-member action.

Owner transfer can be represented in the backend role model but does not need full UI in this milestone.

### Global Discovery

Global search becomes a discovery surface across:

- Contacts/friends.
- Existing group conversations.
- Circles the current user belongs to.
- Circle channels the current user can access.
- Existing message search results.

Results should be grouped by type and navigate to the relevant surface. Search remains private and scoped to the current user's memberships.

### Media Center

Each chat thread gets a media entry point. The media center lists attachments from that conversation:

- Images with thumbnails and preview.
- Voice messages with playback.
- Files as named rows when file messages exist later.

The v1 media center can open image preview and play voice messages. Jumping back to the original message is useful but can be added later if it complicates the current chat thread state.

## Data Model

Add these core tables:

- `circles`: id, name, avatar, owner_id, created_at, updated_at.
- `circle_members`: circle_id, user_id, role, created_at.
- `circle_channels`: id, circle_id, conversation_id, name, position, created_by, created_at, updated_at.
- `circle_posts`: id, circle_id, author_id, body, attachment, deleted_at, created_at, updated_at.
- `circle_post_likes`: post_id, user_id, created_at.
- `circle_post_comments`: id, post_id, author_id, body, deleted_at, created_at, updated_at.

Channel chat should reuse `conversations` with a channel-compatible type if the current schema supports it, or use the existing conversation shape with a new channel-backed reference. Messages should continue to flow through `messages`, `conversation_members`, and the current chat thread UI.

Extend existing group metadata with:

- `announcement`.
- `announcement_updated_at`.
- `announcement_updated_by`.

If the current group table already has a profile/update RPC, prefer extending it over creating a parallel group settings path.

## Backend Rules

- A user can read a Circle only if they are in `circle_members`.
- A user can read a Circle channel only if they are in that Circle.
- A user can post, comment, or like only inside Circles they belong to.
- Only Circle owner/admin can invite members or create channels.
- Only Circle owner can rename the Circle in v1 unless the existing UX makes admin rename obviously expected.
- Blocking still applies to direct interactions. Circle membership does not automatically remove both users from a shared Circle in v1.
- A user cannot invite someone who is not their friend unless later invite links are added.
- A blocked relationship should prevent direct friend-style invites between those users.

Use Supabase RPCs for writes that require membership checks, role checks, or multi-table creation. Keep client-side direct table reads limited to RLS-protected member-scoped selects.

## Frontend Architecture

Follow the existing feature structure:

- `lib/features/circles`: Circle list, detail, creation, member invite, channels, and feed UI.
- `lib/features/groups`: announcement editing and display.
- `lib/features/chats`: media center and channel-thread integration.
- `lib/features/search` or existing global search module: grouped discovery results.
- `lib/shared/models`: Circle, CircleMember, CircleChannel, CirclePost, CircleComment, MediaAttachment.

Repositories should hide Supabase RPC details from widgets. Widgets should be testable with fake repositories, following the existing contacts/chats/settings patterns.

## Navigation

Add routes for:

- `/circles/:circleId`
- `/circles/:circleId/channels/:channelId`
- `/circles/:circleId/posts/:postId` if post deep links are cheap; otherwise defer.
- `/chats/:conversationId/media`

Channel routes should eventually open the existing chat thread with channel title/avatar metadata. If route nesting becomes awkward, use the conversation id as the primary chat route and keep Circle/channel metadata in route extra or repository lookup.

## Error Handling

- Creation failures show inline errors and keep entered text.
- Invite failures should distinguish "not allowed" from generic failure where possible.
- Feed post image upload failures should clear progress and show the root error, matching image message behavior.
- Permission failures should return the user to a safe screen with a concise message.
- Empty states should be useful but not instructional-heavy.

## Testing Strategy

Backend schema tests should assert:

- Circle tables, role checks, and RLS policies exist.
- Circle creation creates owner membership and default channel.
- Channel conversations are connected to Circle channels.
- Circle post/comment/like/report write paths require membership.
- Group announcement RPCs enforce owner/admin permissions.

Repository tests should cover:

- Circle list/detail mapping.
- Circle creation RPC payload.
- Invite member RPC payload.
- Feed post creation, like/unlike, comment, delete, and report calls.
- Media center attachment mapping.

Widget tests should cover:

- Circle empty state and creation.
- Circle detail renders channels and feed.
- Tapping a channel opens the chat thread.
- Posting text/image to Circle feed.
- Liking/commenting/deleting/reporting posts.
- Group announcement display/edit permissions.
- Grouped global search results.
- Media center image and voice entries.

Full verification remains:

- `rtk flutter analyze`
- `rtk flutter test`
- `rtk supabase db push --yes`
- Remote schema/function spot checks after migration push.

## Rollout Plan

This is one product milestone but should be implemented in independent slices:

1. Circle backend foundation and models.
2. Circle list/detail/channel chat.
3. Circle feed posts, likes, comments, and reports.
4. Group announcements and permission cleanup.
5. Global discovery.
6. Chat media center.
7. Final integration, remote migration push, and regression pass.

Each slice should be independently testable. Circles should work after slice 2 even if feed/search/media are still in progress.

## Future Extensions

- Owner transfer UI.
- Invite links with expiry.
- Channel mute/follow settings.
- Circle notification preferences.
- Rich feed post editing.
- Feed mentions.
- Original-message jump from media center.
- Public or semi-public Circle discovery if the product direction changes.
