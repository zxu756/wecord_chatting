# Discord gap batch

Features Discord has that WeCord lacked, picked from the 2026-10-14 gap
review and done in this order. Same rules as the roadmap: observed behavior
only (no Discord code, branding or colors), one commit per item, migrations
pushed to the remote project after each item.

## 1. Bans and timeouts

- [x] Permissions `ban_members` (1 << 15) and `moderate_members` (1 << 16);
      `circle_all_permissions()` and the role range check grow to 17 bits.
- [x] `circle_bans (circle_id, user_id, reason, banned_by, created_at)`;
      readable by members who can ban, written only through RPCs. A trigger
      on `circle_members` refuses banned users on every join path (invites,
      friend invites, discovery).
- [x] `ban_circle_member(circle, user, reason, delete_message_hours)`: same
      rank rules as kick, removes the member, optionally deletes their circle
      messages from the last 1 h / 24 h / 7 days, works for non-members too
      (pre-emptive bans). `unban_circle_member`, `list_circle_bans`.
- [x] `circle_members.timed_out_until`; `timeout_circle_member(circle, user,
      seconds)` (up to 28 days, 0 removes it). While timed out, a member's
      circle and channel permissions shrink to `view_channel`, so sending,
      reacting, threads, invites and voice all stop; they leave voice at once.
- [x] Audit log entries for ban, unban, timeout and timeout removal.
- [x] Client: Ban / Time out / Remove timeout in member actions, a Bans page
      in circle settings with Unban, a timeout badge in the member list, and
      the composer explains the timeout and when it ends.

Notes: reactions and poll votes don't go through `send_messages`, so a
trigger stops timed-out members there. The circle detail reloads when the
current user's timeout ends, since the server lifts it by the clock alone.

## 2. Dark mode

- [x] Dark color scheme next to the light one; Settings → Appearance with
      System / Light / Dark, remembered on the device.
- [x] Hard-coded light colors (rail, bubbles, badges) checked in both themes.

## 3. Delete account

- [x] Settings → Delete account: confirm by typing the username, then the
      `delete-account` Edge Function runs `prepare_account_deletion()` as the
      user and removes their avatar files and login with the service role.
- [x] Like Discord, messages stay under a "Deleted User" profile:
      `profiles.deleted_at`, the profile no longer cascades from
      `auth.users`, and nobody can message or befriend a deleted account;
      search leaves them out.
- [x] Owned circles with other members must be transferred first (409
      `owns_circles`); owned circles with nobody else are deleted. Groups
      they solely own pass to the member who joined first.

## 4. Direct message calls

- [x] `direct_calls` (one active per chat), `direct_call_participants`
      (heartbeat like voice states; one call per person, never a call and a
      voice channel at once) and `direct_call_declines`; RPCs to start or
      join, rejoin, heartbeat, leave and decline, and
      `list_active_direct_calls` with who rings.
- [x] Starting a call posts "X started a call."; when it ends the message
      becomes "X started a call that lasted N minutes."
- [x] `livekit-token` also takes `{call_id}` (room `call-<id>`), checked by
      `can_current_user_join_direct_call`; blocked or deleted accounts can't
      call.
- [x] Client: one voice session for channels and calls; call and video call
      buttons in direct and group chats (the call button sits next to search
      in direct chats on phones), the call above the messages with the usual
      controls, a Join bar when others are in one, and an incoming call
      prompt (Decline / Join with video / Join) anywhere in the app.

## 5. Files and videos

- [ ] Send any file (size limit) and videos from the attach menu; file
      cards with name, size and download; video player in the thread.

## 6. Chinese interface

- [ ] Localize the UI (English and Simplified Chinese), following the
      device language with an override in Settings.

## 7. Push notifications

- [ ] Device tokens table, an Edge Function that sends to FCM / APNs / Web
      Push on new messages for members who are offline, honoring mute and
      notification settings. Needs Firebase and Apple keys from the owner.
