# WeCord

WeCord is a familiar-social real-time chat app: WeChat-first private and group messaging with a lightweight Discord-style circles and channels layer.

## Stack

- Flutter for iOS, macOS, and Web
- Supabase Auth, Postgres, Realtime, Storage, and Edge Functions
- Riverpod, go_router, and flutter_test for app state, navigation, and tests
- LiveKit reserved for future voice and video features

## Local Setup

1. Install Flutter.
2. Copy `.env.example` to `.env`.
3. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
4. Run `flutter pub get`.
5. Run `flutter test`.

## Run

Pass local config with dart defines. The `.env` file is not bundled as a Flutter asset.

```bash
flutter run -d macos --dart-define-from-file=.env
flutter run -d chrome --dart-define-from-file=.env
```

## Current Status

The foundation, private chat, social chat v2, local notifications MVP, and daily chat polish v3 milestones are implemented. WeCord now has email auth, profile bootstrap, friend search and requests, contact aliases, direct and group conversations, text/image/voice messages, unread counts, realtime message refresh, online status, typing indicators, read receipts, profile settings with avatars, reply/edit/recall/forward actions, in-thread and global message search, local message notifications, and notification preview controls.

## Social Chat v2 MVP

This milestone adds group chat creation, group details, editable profile settings, private avatar uploads, reply and edit message actions, conversation search, friend filtering, and in-thread message search.

Apply the Supabase migration before running against a real project:

```bash
supabase db push
```

Next milestones are richer group management, circles/channels, remote push notifications, and deeper chat polish.

## Daily Chat Polish v3

This milestone adds contact aliases, voice message recording/playback, message forwarding, and global message search. It completes the daily-driver chat layer before WeCord moves into familiar-social features such as moments, shared albums, and later Discord-style circles/channels.
