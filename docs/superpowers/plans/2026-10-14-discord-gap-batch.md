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

- [ ] Settings → Delete account: confirm by typing the username, then an
      Edge Function deletes the auth user with the service role. Owned
      circles must be transferred or deleted first.

## 4. Direct message calls

- [ ] Voice/video calls in direct and group chats over the same LiveKit
      setup: ringing for the other members, accept / decline, call panel.

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
