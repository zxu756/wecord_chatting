# WeCord Social Chat v2 MVP Design

## Goal

Make WeCord feel like a fuller familiar-social chat app by adding four visible product areas in one MVP milestone: group chats, profile/settings polish, richer message interactions, and search.

The milestone should make the app feel substantially more complete without trying to build the full Discord-like circle/channel system yet. The guiding rule is: ship the core workflow for each area, keep permissions and edge cases conservative, and leave obvious extension points for later.

## Non-Goals

- Public servers, circle channels, roles, or moderation tools.
- Push notifications.
- Offline message queueing.
- Full global message indexing.
- Username changes.
- Complex group admin roles beyond the initial creator-level controls.
- Message reactions, voice, calls, stickers, or files beyond existing image messages.

## Product Scope

### Group Chat MVP

Users can create a group conversation from existing friends.

Core flows:
- Contacts screen exposes a `New Group` entry point.
- User selects at least two friends.
- User enters a group name.
- App creates a group conversation and membership rows.
- App navigates directly into the new group thread.
- Group threads reuse the existing chat thread UI for text, images, realtime refresh, typing, read markers, and message actions where possible.
- Group detail view shows group name and member list.
- Group creator can rename the group and add more friends.

MVP constraints:
- No removing members.
- No leaving groups.
- No ownership transfer.
- No invite links.
- No channel list inside groups.

### Profile And Settings MVP

Settings becomes a useful account/profile page instead of a placeholder.

Core flows:
- User can view current profile.
- User can edit display name and bio.
- User can upload/change avatar.
- Username remains read-only.
- User can sign out from Settings.
- Avatars appear in contacts, chat list, and the chat thread app bar where the profile is available.

MVP constraints:
- Avatar upload uses Supabase Storage.
- If avatar upload fails, profile text changes should not be lost.
- No avatar cropping UI.
- No profile visibility/privacy settings.

### Message Experience MVP

Existing message actions expand beyond copy/delete/preview.

Core flows:
- Long press or right-click a message includes `Reply` when the message is not recalled.
- Composer shows a reply preview while replying.
- Sent reply messages store a reference to the parent message.
- Message bubbles render a compact quoted preview above the body/image.
- Long press or right-click on the current user's non-recalled text message includes `Edit`.
- Editing a message pre-fills the composer or opens a small edit surface.
- Edited messages update the existing row and display an edited marker.
- Failed sends keep the composer content available so the user can try again.

MVP constraints:
- Reply preview stores enough denormalized display text to survive parent edits/deletes.
- Only text messages can be edited.
- Recalled messages cannot be replied to or edited.
- No offline retry queue.
- No reactions in this milestone.

### Search MVP

Search should make the current app easier to navigate.

Core flows:
- Chats screen gets a search field.
- Chat search filters conversation title, participant display name, username, and latest message preview.
- Contacts keeps profile search and friends list filtering.
- Chat thread gets in-conversation search.
- Thread search returns matching messages in the current conversation.
- Selecting a thread search result scrolls to that message in the current conversation.

MVP constraints:
- No global search page.
- Use simple case-insensitive matching for MVP instead of adding full-text search indexes.
- Message highlight is deferred; scroll-to-result is the visible result behavior for this milestone.

## Data Model

### Existing Tables To Extend

`conversations`
- Use existing `type` to distinguish direct and group conversations.
- Use existing nullable `title` field for group names.

`conversation_members`
- Continue to represent group members.
- Use existing `role` field; the group creator is inserted as `owner`, added friends are inserted as `member`.

`messages`
- Use existing `reply_to_message_id uuid null references public.messages(id)`.
- Add `reply_preview jsonb null`.
- Use existing `edited_at timestamptz null`.
- Continue using `recalled_at` for delete/recall.

`profiles`
- Use existing `avatar_url`.
- Continue using `display_name`, `username`, and `bio`.

### New Storage Usage

`profile-avatars`
- Stores user avatar images.
- Path format: `{user_id}/{timestamp-or-seed}-{safe-file-name}`.
- Read access should be limited to authenticated users for MVP, matching familiar-social assumptions.
- Write access should be limited to the owner.

## Backend And Security

Use narrow RPCs for operations that should not expose broad update policies.

RPCs:
- `create_group_conversation(group_title text, member_ids uuid[]) returns uuid`
- `rename_group_conversation(conversation_id uuid, group_title text) returns void`
- `add_group_members(conversation_id uuid, member_ids uuid[]) returns void`
- `update_current_user_profile(display_name text, bio text, avatar_url text) returns void`
- `edit_message(target_message_id uuid, body text) returns void`

Security rules:
- Group creation only allows adding current user's accepted friends.
- Creator can rename group and add members.
- Message editing only allows sender editing their own non-recalled text messages.
- Replies require the replied-to message to be in the same conversation and visible to the sender.
- Profile updates only affect the current user's profile.
- Storage policies only allow writing avatars under the current user's own folder.

## Flutter Architecture

Follow the existing feature layout.

New or extended modules:
- `features/groups`: group creation and group detail UI if the code grows too large for contacts/chats.
- `features/settings`: settings repository/controller if profile update logic becomes non-trivial.
- `features/chats`: reply/edit state, thread search, and group-aware chat rendering.
- `shared/models`: group/member profile projections, reply preview, edited message fields.

Repository changes:
- Extend `ChatsRepository` with group creation, group member management, message edit, and thread search.
- Add or extend a profile/settings repository for updating display name, bio, and avatar.
- Keep Supabase-specific details behind repositories/data sources.

UI behavior:
- Keep group chat visually close to direct chat at first.
- Add small avatar treatment in lists and headers.
- Use modal sheets for group creation, message edit, and group detail actions where this fits current Flutter patterns.
- Keep empty/loading/error states explicit.

## Testing

Database/schema tests:
- Group RPCs exist and enforce friend/member constraints.
- No broad update policies are introduced for sensitive tables.
- Message edit RPC is sender-scoped and text-only.
- Profile update RPC is current-user scoped.
- Avatar storage policy path ownership is represented in migration text.

Repository tests:
- Group creation calls the correct RPC and returns conversation id.
- Rename/add member RPCs are wired correctly.
- Profile update and avatar upload are wired correctly.
- Edit message calls the narrow RPC.
- Thread search maps matching messages.

Widget tests:
- Contacts can start group creation from friends.
- Group thread opens after creation.
- Settings edits profile fields and signs out.
- Avatar upload success/error states render correctly.
- Reply flow stores reply state and sends a reply.
- Edit flow updates an outgoing text message.
- Chats search filters visible conversations.
- Thread search shows current-conversation results.

Verification:
- `rtk flutter analyze`
- `rtk flutter test`
- `rtk supabase db push`

## Rollout Order

1. Database migrations and model updates.
2. Repository and data-source APIs.
3. Group creation and group thread reuse.
4. Settings/profile editing and avatar upload.
5. Reply and edit message flows.
6. Chats and thread search.
7. Full verification and push.

This order keeps backend contracts stable before UI work and lets the existing direct chat functionality keep working while group and message features are added.
