# AI features: setup

WeCord's AI features (catch-up summaries, rewriting a draft in the composer,
translating a message) run through one Edge Function, `supabase/functions/ai/`.
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

Errors are `{error: <code>}`: `unauthorized` (401), `invalid_request` (400),
`ai_not_configured` (503), `ai_disabled_in_circle` (403), `ai_limit_reached`
(429, with `limit` and `used`), `ai_busy` (503, the provider's own limits),
`ai_failed` (502), `conversation_not_found` (404), `text_too_long` (413).

### Privacy and safety

- **Messages are read as the caller.** A summary uses the user's own token, so
  row level security decides what is visible: nothing the user cannot see in
  the app reaches the model. Recalled messages are left out.
- **Nothing is stored.** Only a per-user, per-day request count is kept
  (`ai_usage`, readable by its owner, written by the function with the service
  role). Message text is not logged or saved, and translations are cached on
  the user's device only.
- **Chat is data, not instructions.** Prompts fence the chat and the user's
  text between tags, tell the model to ignore any instruction inside them and
  never to invent messages, and the function strips control characters, chat
  template tokens and the fence tags from the content first.
- **Limits.** Each request counts against `AI_DAILY_LIMIT_PER_USER` before the
  provider is called, and is given back if the provider fails.
- **Controls.** Each user can turn AI off in Settings → AI (on this device).
  Circle managers can turn it off for a circle (Circle settings → Allow AI
  features in this circle); the function then answers `ai_disabled_in_circle`
  for that circle's channels and threads.

## Tests

```sh
cd supabase/functions/ai && deno test
flutter test test/features/ai
```
