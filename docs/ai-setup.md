# AI features: setup

WeCord's AI features (catch-up summaries, rewriting a draft in the composer,
translating a message, and on the web transcribing a voice message) run through
one Edge Function, `supabase/functions/ai/`.
It talks to any **OpenAI-compatible Chat Completions** provider. Which provider
and model is decided only by secrets, so switching providers never needs a code
change or an app update.

Until the three required secrets are set the function answers
`503 ai_not_configured`, and the app hides its AI buttons (Settings → AI
explains why).

## Secrets

| Secret | Required | Meaning |
| --- | --- | --- |
| `AI_BASE_URL` | yes | The provider's API root, without `/chat/completions`. Must be `https` (plain `http` only for `localhost`). |
| `AI_API_KEY` | yes | The provider's key. Sent as `Authorization: Bearer <key>`. |
| `AI_MODEL` | yes | The model name the provider expects. |
| `AI_DAILY_LIMIT_PER_USER` | no | AI requests one user may make per UTC day. Default `50`. |
| `AI_MAX_INPUT_CHARS` | no | Characters of chat (or text) sent to the model per request. Default `24000`. The newest messages are kept first. |
| `AI_TRANSCRIBE_BASE_URL` | no | An OpenAI-compatible speech-to-text API root, without `/audio/transcriptions` (see "Voice message transcription"). `https` only (plain `http` for `localhost`). |
| `AI_TRANSCRIBE_API_KEY` | no | That provider's key. |
| `AI_TRANSCRIBE_MODEL` | no | The transcription model name, e.g. `whisper-1`. |
| `AI_EXTRA_HEADERS` | no | A JSON object of extra request headers for providers that need them, e.g. `{"x-team":"wecord"}`. `Authorization`, `Content-Type`, `Accept`, `Host`, `Content-Length` and `User-Agent` cannot be set this way. |

Set them on the project (the key is a secret: never commit it and never put it
in an `.env` file that is checked in):

```sh
supabase secrets set \
  AI_BASE_URL=<provider-base-url> \
  AI_API_KEY=<your-api-key> \
  AI_MODEL=<model-name>

# optional
supabase secrets set AI_DAILY_LIMIT_PER_USER=30 AI_MAX_INPUT_CHARS=24000
supabase secrets set AI_EXTRA_HEADERS='{"x-team":"wecord"}'
```

The function reads them on each request, so a new value applies right away
(no redeploy needed). Apply the database migrations first (the function calls
`ai_consume_request` and `conversation_ai_allowed`), then deploy the function
itself once:

```sh
supabase functions deploy ai
```

Check it: in the app open Settings → AI. It shows how many requests you have used today once the function
sees all three secrets, and a note that AI is not set up otherwise.

## Provider examples

### OpenCode Go (the default for WeCord)

```sh
supabase secrets set \
  AI_BASE_URL=https://opencode.ai/inference/go/openai/v1 \
  AI_API_KEY=<your-opencode-api-key> \
  AI_MODEL=deepseek-v4.1-flash
```

OpenCode asks clients to identify themselves and to send a stable session id
per conversation. The function does both without any setting: it sends
`User-Agent: WeCord/1.0 (+https://wecord.jokebear.fyi)` (always WeCord's own,
never another client's) and, when the base URL is on `opencode.ai`, an
`x-opencode-session` header: the first 32 hex characters of the SHA-256 of
`<conversation id>:<feature>`.

OpenCode Go has spending caps per 5 hours, week and month. When one is
reached the provider answers HTTP 429 or 402; WeCord shows "AI is busy right
now. Try again in a little while." and does not count the request against the
user's own daily limit. (That daily limit, `AI_DAILY_LIMIT_PER_USER`, is
WeCord's own and shows a different message.)

### DeepSeek's official API

```sh
supabase secrets set \
  AI_BASE_URL=https://api.deepseek.com/v1 \
  AI_API_KEY=<your-deepseek-api-key> \
  AI_MODEL=deepseek-chat
```

### Any other OpenAI-compatible provider

Use the provider's documented base URL (the part before `/chat/completions`)
and a model name from its list:

```sh
supabase secrets set \
  AI_BASE_URL=https://<host>/<path>/v1 \
  AI_API_KEY=<key> \
  AI_MODEL=<model>
```

OpenAI itself is `https://api.openai.com/v1`; a local Ollama is
`http://localhost:11434/v1` (any non-empty key). If the provider wants an extra
header, put it in `AI_EXTRA_HEADERS`.

To switch providers later, run `supabase secrets set` again with the new three
values. Nothing else changes.

## Voice message transcription

Voice messages have a **Transcribe** button. Where it runs:

- **iPhone and Mac apps:** on the device, with the system's speech recognizer
  (`SFSpeechRecognizer`, in `ios/Runner/TranscribePlugin.swift` and
  `macos/Runner/TranscribePlugin.swift`). Nothing is sent to WeCord's server.
  If the device cannot recognize the language on its own, the app says so and
  only sends the audio to Apple's speech service after the person agrees.
  Needs no secrets.
- **Web:** a browser cannot transcribe a file on its own, so the web calls the
  `ai` function's `transcribe` action, which needs the three optional secrets
  `AI_TRANSCRIBE_BASE_URL`, `AI_TRANSCRIBE_API_KEY` and `AI_TRANSCRIBE_MODEL`
  **on top of** the three required ones. Without them the function answers
  `503 transcribe_not_configured` and the web says "Transcription is
  available in the iPhone and Mac apps."

```sh
supabase secrets set \
  AI_TRANSCRIBE_BASE_URL=https://api.openai.com/v1 \
  AI_TRANSCRIBE_API_KEY=<your-api-key> \
  AI_TRANSCRIBE_MODEL=whisper-1
```

The provider only has to accept OpenAI's `POST {base}/audio/transcriptions`
(multipart: `file`, `model`, `response_format=json`) and answer `{"text": …}`.
It is independent of the chat provider, so the two can be different
companies. The status answer carries `transcribe_configured` so the app knows
whether to offer it.

How the function treats it:

- The app sends only the **message id**. The function loads the message as the
  caller (row level security), takes the audio's bucket and path from the
  message itself, and downloads the audio with the caller's own storage access.
  A message the caller cannot see is `404 message_not_found`.
- The same switches as every AI feature apply: the person's Settings → AI
  switch (the app does not offer it while off), the circle's switch (checked
  from the message's own conversation: `403 ai_disabled_in_circle`) and the
  daily limit `AI_DAILY_LIMIT_PER_USER` (one transcription is one request,
  given back when the provider fails: `429 ai_limit_reached`).
- Audio over 25 MB is refused (`413 audio_too_long`) before anything is sent.
- The audio is sent to the provider for that request and not kept; the
  transcript is **not stored on the server**. The app keeps it on the
  person's device only (per signed-in user), so it is private to whoever
  transcribed it.
- Settings → AI → "Auto-transcribe voice messages" (default off) only ever
  works on the device (iPhone and Mac); it never calls the server by itself.

## Local development

```sh
supabase start
supabase functions serve ai --env-file supabase/functions/ai/.env.local
```

where `supabase/functions/ai/.env.local` (git-ignored) holds the same names as
above. The app finds the function at `http://127.0.0.1:54321/functions/v1/ai`.

## What the function does

`POST /functions/v1/ai` with a signed-in user's token and a JSON body:

| `action` | Fields | Answer |
| --- | --- | --- |
| `status` | | `{configured, daily_limit, used}` |
| `summarize` | `conversation_id`, optional `after_message_id`, `recent`, `language` (`en`/`zh`) | `{summary, message_count, summarized_count, first_message_id}` |
| `rewrite` | `mode` (`fix`/`shorter`/`polite`/`formal`/`translate`), `text`, `target` for `translate`, optional `conversation_id` | `{text}` |
| `translate` | `text`, `target` (`en`/`zh`/`ja`/`ko`/`es`/`fr`), optional `conversation_id` | `{text}` |
| `transcribe` | `message_id` of a voice message | `{text}` (empty when no speech was found) |
| `translate_batch` | `conversation_id`, `message_ids` (up to 20), `target`, optional `manual` | `{target, translations: {id: {text, source_lang}}, skipped: {id: reason}, cached, translated}` |

Errors are `{error: <code>}`: `unauthorized` (401), `invalid_request` (400),
`ai_not_configured` (503), `ai_disabled_in_circle` (403), `ai_limit_reached`
(429, with `limit` and `used`), `ai_busy` (503, the provider's own limits),
`ai_failed` (502), `ai_disabled_for_user` (403, translate_batch: the person turned AI off), `too_many_messages` (400, translate_batch), `conversation_not_found` (404), `text_too_long` (413), and for `transcribe`
`transcribe_not_configured` (503), `message_not_found` (404), `audio_too_long`
(413).

### Translating messages (`translate_batch`)

Auto-translate ("Auto-translate this chat" in the chat's More menu), the
message menu's Translate and nothing else use this action; it is the only
translation path that touches messages. The app sends the ids of the messages
that are on screen (never the whole history), and the function:

1. refuses a circle that turned AI off (`ai_disabled_in_circle`) and a person
   who turned AI off (`ai_disabled_for_user`, copied from Settings → AI into
   `user_ai_settings.ai_enabled`), before reading anything;
2. reads the messages as the caller and never translates or returns one that
   is recalled, expired, waiting for or removed by the AI guard, not text, or
   not visible to the caller (`skipped: unavailable`);
3. skips text without letters (emoji, links, @mentions), text already in the
   target language by its script, and languages in the person's "Don't
   translate" list, without a model call;
4. answers from the cache `message_translations` (one row per message and
   language), which costs nothing against the daily limit, even at the limit;
5. sends the rest to the model as ONE request (up to about 6000 characters),
   which counts once against `AI_DAILY_LIMIT_PER_USER` and is given back if
   the provider fails or answers badly, and stores the answers.

`manual: true` (the message menu) skips the language rules of step 3. The cache
holds message text, so it goes with the message: a trigger clears it when the
message is edited, recalled (including moderator delete), held or removed by
the guard, or moved to expired, and the foreign key deletes it when the message
is purged or its account or conversation is deleted. Only the service role
writes it, through `store_message_translations`, which refuses text that has
changed since it was translated. The function must be redeployed
(`supabase functions deploy ai`) after migrations 202610220400 and
202610220410.

### Privacy and safety

- **Messages are read as the caller.** A summary uses the user's own token, so
  row level security decides what is visible: nothing the user cannot see in
  the app reaches the model. Recalled messages are left out.
- **Little is stored.** A per-user, per-day request count is kept (`ai_usage`,
  readable by its owner, written by the function with the service role).
  Message text is not logged. The one exception is the translation cache,
  below; voice message transcripts stay on the user's device only.
- **Chat is data, not instructions.** Prompts fence the chat and the user's
  text between tags, tell the model to ignore any instruction inside them and
  never to invent messages, and the function strips control characters, chat
  template tokens and the fence tags from the content first. (Transcription
  sends audio, not text, and returns only the provider's transcript.)
- **Limits.** Each request counts against `AI_DAILY_LIMIT_PER_USER` before the
  provider is called, and is given back if the provider fails.
- **Controls.** Each user can turn AI off in Settings → AI (on this device).
  Circle managers can turn it off for a circle (Circle settings → Allow AI
  features in this circle); the function then answers `ai_disabled_in_circle`
  for that circle's channels and threads.

## AI guard for new members

Circle managers can turn on **AI guard for new members** (Circle settings → AI
guard; off by default, and only while the circle's AI switch is on). The first
messages of a new member (joined less than 1, 3 or 7 days ago, or fewer than N
messages in the circle) wait for a check before the others see them. A message
the AI flags stays held for the moderators (Hold) or is released with a flag
(Flag); moderators decide in the circle's Review queue. Moderators, managers,
bots and the owner are never held, and only text messages are checked (pictures
and files are not).

How a check runs, and why the database starts it:

1. A trigger on `messages` (`202610170090_ai_guard.sql`) marks a message from a
   guarded member `checking`. Every way of sending goes through it (the app,
   scheduled sends, the REST API), so a client cannot skip the check or choose
   its own state. Others cannot see the message, count it as unread or
   mentioned, search it, or be pushed about it until it is released.
2. The same insert posts to `POST /functions/v1/ai` through **pg_net**, with
   `{"action": "guard", "message_id": ...}` and the shared secret as bearer
   token. It starts the moment the message is stored, needs no cron delay and
   cannot be skipped by a client. (The alternative, the sender's app calling
   `ai` after sending, would let a modified client leave messages unchecked
   or released, and would need a cron sweep anyway for apps that go offline
   between the send and the call.)
3. The function claims the message, counts the request against the **circle**
   (`ai_circle_usage`, limit `AI_GUARD_DAILY_LIMIT_PER_CIRCLE`, default 500
   per UTC day; never the member), classifies the text and the hosts of its
   links into `allow` / `spam` / `scam` / `harassment` / `sexual` / `other` with
   a short reason, and hands the answer to `finish_message_review`. It uses
   the same `AI_BASE_URL` / `AI_API_KEY` / `AI_MODEL` as every other feature,
   at temperature 0 with a 15 second timeout.
4. **Fail open.** If the AI is not set up, the circle turned it off, the
   circle's limit is reached, the provider fails, answers badly or is too slow,
   or the database cannot reach the function (no pg_net or Vault secrets), the
   message is released and recorded as "not checked" with the reason. A sweep
   (`run_ai_guard_sweep`, every minute through pg_cron) releases checks that
   never came back after 60 seconds. AutoMod keeps working: its triggers run
   before the guard and can still block the message.
5. Releasing moves the message to the end of the chat (when it waited), updates
   the conversation's latest message and queues the push. `scheduled-dispatch`
   claims it (`claim_released_message_pushes`) and pushes it through
   `claim_push_delivery`; the release also wakes `scheduled-dispatch` through
   pg_net, so it is prompt.

Set up (once, besides the usual AI secrets):

- The Vault secrets `wecord_functions_url` and `wecord_dispatch_secret` and the
  function secret `DISPATCH_SECRET` (the same ones `scheduled-dispatch` uses,
  see `supabase/functions/scheduled-dispatch`). Without them messages are
  released unchecked.
- Deploy `ai` so the gateway lets the shared secret through: `verify_jwt = false`
  is set in `supabase/config.toml` (the function authenticates every other
  request itself). With the CLI: `supabase functions deploy ai` (it reads the
  config) or `--no-verify-jwt`. Redeploy `scheduled-dispatch` too.
- Optional: `supabase secrets set AI_GUARD_DAILY_LIMIT_PER_CIRCLE=200`.

Privacy: only the **text** of messages from guarded members, and the host names
of its links, is sent to the model, and only while the guard is on. Nothing is
stored beyond the category and a short reason (`message_reviews`, readable by
moderators), and the circle's daily request count.

## Tests


```sh
cd supabase/functions/ai && deno test
flutter test test/features/ai test/features/transcribe test/supabase/ai_guard_test.dart
```
