# Voice, chat, safety and profile batch

The rest of the 2026-10-14 gap review plus the leftovers from earlier
batches. Same rules as before: observed behavior only (no Discord code,
branding or colors), one commit per item, migrations pushed to the remote
project after each item, every new `tr()` string translated.

Work runs in parallel worktrees by area, so migration numbers are fixed
here up front and new Chinese strings go in a new area map per worktree.

## Wave A

### Presence and profile (`zh_profile_more.dart`)
1. Away, Do Not Disturb and Invisible next to Online; DND silences local
   and push notifications; Invisible shows as offline to others. A
   Settings switch for the existing `show_online_status`.
   Migration `202610160001`.
2. Profile banner image, pronouns, a per-circle avatar, and mutual
   friends and mutual circles on profile cards. Migration `202610160002`.

### Chat experience (`zh_chat_more.dart`)
3. Unsent drafts kept per conversation; Ctrl/Cmd+K quick switcher and
   keyboard shortcuts (a list of them under `Ctrl+/`). No migration.
4. `@here` (members online now) and `@role` mentions, with role mentions
   respecting a per-role "anyone can mention" flag. Migration
   `202610160003`.
5. GIF search in the composer through a `gif-search` Edge Function that
   holds the provider key; off until the key is set. No migration.

### Voice (`zh_voice_more.dart`)
6. Push to talk with a chosen key, noise suppression, and a volume slider
   per participant (local only).
7. Server mute and deafen, disconnect, move to another channel, and a
   user limit per voice channel. New permissions `mute_members`,
   `deafen_members`, `move_members`. Migration `202610160004`.
8. Text chat inside voice channels. Migration `202610160005`.

### Leftovers (`zh_leftovers.dart`)
9. Custom emoji lists refresh live; group admins (not only the owner) can
   pin; the reactions query gets the index or rewrite it needs; files of
   deleted channels are removed from storage. Migrations `202610160014` to
   `202610160017`.
10. Branded web icons and manifest; `wrangler.jsonc` and a deploy script in
    the repo; sign-up and reset emails redirect to the web app's own URL.

Wave A is merged (presence, profile, chat, voice and leftovers), with
its migrations pushed. Wave B numbers start after the leftovers' 0017 so
they sort after everything already on the remote.

## Wave B (after wave A is merged)

### Moderation and safety
11. AutoMod: keyword and pattern filters, spam limits, and actions (block,
    alert channel, timeout). Migration `202610160020`.
12. Member onboarding: rules to accept before chatting, then a welcome
    screen. Migration `202610160021`.
13. Two-step verification with an authenticator app (Supabase MFA TOTP).

### Circles
14. Announcement channels that other circles can follow, with a publish
    action that forwards posts. Migration `202610160022`.
15. Circle templates (create a circle from a saved layout). Migration
    `202610160023`.
16. Circle tags shown next to member names. Migration `202610160024`.
17. A bot API: bot accounts with tokens and a REST Edge Function for
    reading and sending messages and answering slash commands. Migration
    `202610160025`.

### Stage and soundboard
18. Stage channels: speakers and an audience, raising hands, inviting to
    speak. Migration `202610160018`.
19. Soundboard: short uploaded sounds played into voice channels.
    Migration `202610160019`.

### Phone layout
20. A phone home closer to the observed mobile layout: the server rail and
    the conversation panel run edge to edge under the status bar; the
    panel has a title, a search button, an Add Friends button and a new
    message button, a row of online friends, and conversation rows with the
    last message and its age; the bottom tab bar gives way to a floating
    user panel (status, profile, notifications).

## Status

All twenty items are merged into `wecord-foundation`, every migration
through `202610160030` is on the remote project, and the `gif-search`,
`livekit-token`, `delete-account` and `bot-api` functions are deployed.
Still to check by hand: two-person voice (stage, soundboard, server mute),
web push and two-step sign-in on a real device, creating a bot on the
hosted project, and GIF search once `GIPHY_API_KEY` is set.
