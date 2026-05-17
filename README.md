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

The foundation and private chat milestones are implemented. WeCord now has email auth, profile bootstrap, friend search and requests, direct conversations, text messages, unread counts, and basic realtime refresh hooks.

## Private Chat Milestone

This milestone adds email auth, profiles, friends, direct conversations, text messages, unread state, and basic realtime refresh.

Apply the Supabase migration before running against a real project:

```bash
supabase db push
```

Next milestones are group chat, circles/channels, media messages, typing/presence, and notifications.
