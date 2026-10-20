# Crash and error reports

WeCord reports what goes wrong on a device to its own Supabase project. No
third-party service is involved. Code: `lib/features/error_reports/`;
database: `supabase/migrations/202610190030_client_errors.sql`.

## What is captured

| kind | when |
| --- | --- |
| `flutter_error` | `FlutterError.onError` |
| `platform_error` | `PlatformDispatcher.instance.onError` |
| `zone_error` | an uncaught error in the app's zone (`runReportingErrors`) |
| `provider_error` | a Riverpod provider failed (`ProviderObserver`; only failures, network errors left out) |
| `auth_unexpected_sign_out` | a `signedOut` event that did not come from `AuthRepository.signOut` (Sign out, delete account, two-step cancel) |
| `auth_refresh_burst` | more than 5 token refreshes within a minute |
| `router_redirect_loop` | the same redirect more than 8 times within 5 seconds |
| `rpc_error`, `function_error` | a failed RPC or Edge Function call: status and error code only, and only failures that point at a bug or outage (5xx, 401/403/404, `PGRST…`, `42…`); errors the server raises on purpose (`P0001`, `23…`) are not reported |
| `sign_in_error` | the sign-in or sign-up service failing (5xx, 429); a wrong password is not |

Calls are noticed in one place: the HTTP client given to `Supabase.initialize`
(`ErrorReportingHttpClient`). It never changes a request or response.

Breadcrumbs (route templates, auth event names, app lifecycle) are kept in
memory, the last 30; a report carries the last 8 in its context with the
route, the language and nothing else.

## What is never sent

Message text, file names or local paths, emails, tokens, phone numbers, ids
in routes (routes are sent as templates such as `/moments/:postId`), quoted
text from error messages, request or response bodies and the user's id (the
server takes it from the session; it is null for signed-out callers).
`ErrorScrubber` removes JWTs, `Bearer` values, `token=`/`password=`-style
values, emails, URLs down to their host, absolute paths, UUIDs, long opaque
strings and long numbers. Stack traces keep functions and `package:`/`dart:`
libraries only, and are cut to 8 KB. Server errors are described by status
and code, never their text.

## Limits

- On the device: the same fingerprint is one entry with a count; the same
  problem is sent again only after 10 minutes; at most 30 new problems per
  10 minutes; a queue of 30 kept offline (SharedPreferences); at most 10
  reports per batch and 60 per hour; failed uploads back off up to 15
  minutes. The reporter never reports its own failures and drops reports
  made while it is reporting.
- On the server (`report_client_errors(reports jsonb)`, security definer,
  callable by `anon` and `authenticated`): 20 reports and 64 KB per call,
  texts cut to length, kinds from a fixed list, 4 KB of context, and per
  hour 60 reports per user, 10 per anonymous caller (a hash of the address
  salted with the hour), 200 for all anonymous callers and 3000 overall.
  It never raises for bad input; it answers `{accepted, dropped}`.
- Clients cannot read or write `client_errors`; only the owner can.
- Rows older than 30 days are deleted daily (`purge_old_client_errors()`,
  scheduled with pg_cron where installed).

## Opt-out

Settings, Privacy & Safety, "Send crash and error reports" (on by default).
It is per device (SharedPreferences, not the account). Turning it off
deletes what is waiting to be sent.

## Reading the reports

```sh
sh tool/errors_report.sh            # last 24 hours, top 20 groups
sh tool/errors_report.sh 72 50      # last 72 hours, top 50
sh tool/errors_report.sh --local    # the local database
sh tool/errors_report.sh --symbolize   # name the frames of release builds
```

It runs read-only `select`s through `supabase db query --linked`. For one
group's stack and context:

```sh
supabase db query --linked "select stack, context from public.client_errors \
  where group_key = '<group_key>' order by created_at desc limit 1"
```

The admin console shows the same groups in its Alerts tab (last 24 hours).

## Groups (K5)

A device fingerprints a problem from the top five frames of its stack, so one
bug can be several fingerprints. The server adds `group_key` (a trigger on
`client_errors`; `report_client_errors` is untouched): the kind of report, the
type of the error (`context.type`, the class name the device sends, or the
start of the message) and the first frame that is WeCord's own code
(`package:wecord/...`, no line number). Digits do not count. Groups are
remembered in `ops_error_groups` for 90 days: when and in which version each
first showed up. A group with at least 3 reports that was never seen before
raises an alert (monitoring, K3), once.

## Symbols (K5)

Release builds are made with `--split-debug-info=build/symbols/<version>/<platform>`
(see "Build and release" in `docs/WECORD_FEATURES.md`). Their stack traces have
no names, only addresses, and a header with the build id. The device keeps that
header (`ErrorScrubber.stack`), so:

```sh
sh tool/errors_report.sh --symbolize 72 30
```

takes the newest stack of each of the top groups, finds the `.symbols` file
under `build/symbols/<version>/` that matches, runs `flutter symbolize`, and
prints the groups again by kind and first WeCord frame. Keep
`build/symbols/<version>/` for every release you ship; it is in `build/`, never
committed, and a version without it cannot be read. Web reports are minified
JavaScript and are not symbolized.

Build with `--dart-define=APP_VERSION=… --dart-define=APP_BUILD=…` so reports
carry the version and build.
