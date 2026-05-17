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

The foundation milestone contains app setup, typed configuration, theme, routing, and stub screens. Private chat is the next implementation milestone.
