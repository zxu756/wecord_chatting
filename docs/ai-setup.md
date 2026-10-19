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
| `extract_actions` | `conversation_id`, `message_ids` (1 to 50), optional `time_zone` (IANA) and `utc_offset_minutes` | `{items: [{title, assignee, due, due_has_time, due_text, kind, source_message_id}], message_count}` |
| `assistant` | `job_id`; only the database may call it (shared secret) | `{ok, reply_id, kind}` or `{ok, skipped: reason}` |
| `digest` | `digest_id`; only the database may call it (shared secret) | `{ok, chats}` or `{ok, skipped: reason}` / `{ok, failed: reason}` |
| `note_assist` | `note_id`, `mode` (`continue`/`summarize`/`outline`/`tone`/`translate`/`extract_tasks`), optional `text` (the selection, up to 8000 characters), `tone` (`polite`/`formal`/`casual`/`concise`/`fix`) for `tone`, `target` for `translate`, optional `language` | `{blocks: [{kind, text, checked}], text, truncated, source_chars}` |
| `meeting_recap` | `conversation_id`, `entries` (1 to 2000 sentences `{speaker, text, at?}`), optional `language`, `time_zone`, `utc_offset_minutes` | `{title, summary, decisions, action_items, truncated, line_count, speaker_count}` |

Errors are `{error: <code>}`: `unauthorized` (401), `invalid_request` (400),
`ai_not_configured` (503), `ai_disabled_in_circle` (403), `ai_limit_reached`
(429, with `limit` and `used`), `ai_busy` (503, the provider's own limits),
`ai_failed` (502), `ai_disabled_for_user` (403, translate_batch, extract_actions, note_assist, meeting_recap: the person turned AI off), `too_many_messages` (400, translate_batch), `conversation_not_found` (404), `note_not_found` (404, note_assist), `text_too_long` (413), and for `transcribe`
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

### Extracting to-dos (`extract_actions`)

"Extract to-dos" in the selection bar sends the chosen messages (at most 50) and
gets items back that the person confirms in a sheet; nothing is created by the
function. Rules (`supabase/functions/ai/extract_actions.ts`):

- circle switch (`ai_disabled_in_circle`) and the person's switch
  (`ai_disabled_for_user`) are checked before anything is read; recalled,
  expired, AI-guard-held and non-text messages are never read, even if their ids
  are sent; the call counts once against `AI_DAILY_LIMIT_PER_USER` and is given
  back when the model fails or answers badly;
- the model sees a numbered member list and answers with a number; a number out
  of range, a name nobody has, a name two members share or an id that is not a
  member's all become `assignee: null`, so only conversation members can be
  assigned;
- `due` is a wall-clock date the model writes in the requester's time zone (the
  function tells it today's date there) and the function turns it into a UTC
  instant. The zone is the app's IANA name, else its UTC offset, else UTC. A
  date more than a day in the past is dropped; an event with no time of day
  becomes a task. The app re-reads `due_text` with its own time phrase parser
  (the one behind time tokens) and prefers that result.

### The @WeCord AI assistant (`assistant`)

Anybody can write `@WeCord AI <request>` in a chat; `/20` or `/100` right after
the mention lets it read the last 20 or 100 messages the requester can see (no
suffix: only the message and the one it replies to). The app's "Ask WeCord AI"
sheet writes that text. Flow (migrations 202610230400 to 202610230430):

1. a trigger on `messages` notices the mention and queues a row in `ai_jobs`
   (one per message; held messages queue when the AI guard releases them, edits
   and bots never queue; 5 per person per minute), then wakes `POST
   /functions/v1/ai {"action": "assistant", "job_id": ...}` through pg_net with
   `DISPATCH_SECRET`, exactly like the AI guard (same Vault secrets, same
   `verify_jwt = false`). `run_ai_assistant_sweep` (pg_cron, every minute) wakes
   lost jobs up to three times and fails stuck ones;
2. `ai_assistant_claim` takes the job and refuses, in SQL, when the message is
   gone or older than 6 hours, the requester left, the circle turned AI off, the
   group owner turned WeCord AI off (`group_ai_settings`, "WeCord AI in this
   group" in the group's details, owner only), or the requester turned AI off
   (`user_ai_settings.ai_enabled`). Nothing is sent to the model then;
3. the requester's daily limit is counted (`AI_DAILY_LIMIT_PER_USER`); at the
   limit the job is `limited` and nothing is posted;
4. `ai_assistant_context` returns what the model may read, with the requester's
   visibility (`current_user_readable_conversation_ids`), never recalled, expired
   or held messages, plus the member list; the replied-to message and the chat
   log are fenced as untrusted data, the request is the one thing it follows;
5. the answer (JSON: kind answer / summary / translation / rewrite / todos, the
   text, and for todos the items with the same member-only assignees) is posted
   as a reply by the WeCord AI account and marked in `messages.ai_reply`
   (clients cannot write it). Replies can be reported like any message.

**The WeCord AI account.** `system_bots` holds the app's own bot accounts by key;
no user id is written in any migration. SQL cannot create `auth.users` rows on
hosted projects, so the `ai` function creates the login the first time it needs
it, the way the `bots` function does: Auth admin API, banned, random password,
`app_metadata.provider = 'bot'`; then `register_ai_assistant` (service role)
turns it into the profile "WeCord AI" (`is_bot`, username `wecord_ai`, or
`wecord_ai_xxxxxx` if taken). It is idempotent: a racing call keeps one account
and deletes the surplus login. The account is a member of no chat; in circle
channels `check_channel_message_send` lets a message marked `ai_reply` through
(202610230430).

Deploy: apply the migrations, then `supabase functions deploy ai`. Nothing else
to set; the assistant uses the same AI secrets and Vault secrets as the guard.

### The daily digest (`digest`)

Settings → AI → Daily digest: a person follows up to 10 groups or circle
channels and picks a time; every day at that time on their own clock they get
one card in Notifications (and a push "Your daily digest is ready", which names
no chat content) summarising what was said. Migrations 202610230500 to
202610230540:

1. `ai_digest_tick` (pg_cron `wecord-ai-digest-tick`, every minute; the older
   `run_later_dispatch` is untouched) finds people whose clock in their zone
   (`notification_time_zone`: what their devices report, else UTC) has reached
   their time, at most six hours late, once per local day
   (`ai_digests` is unique on user and date). The window is everything since
   their last digest, at most 24 hours;
2. **no news, no model**: before queueing, SQL counts what the person may see
   in the window (`ai_digest_messages`). None: the day is recorded as
   `skipped / no_news` and the `ai` function is never woken, so nothing is
   asked of the AI and nothing counts against the daily limit. Otherwise it
   wakes `POST /functions/v1/ai {"action": "digest", "digest_id": ...}` through
   pg_net with `DISPATCH_SECRET` (same Vault secrets and `verify_jwt = false` as
   the guard and the assistant; lost wake-ups are repeated up to three times by
   the tick, runs that never return fail after four minutes);
3. `ai_digest_claim` re-checks: digest switched off, the person turned AI off
   (`user_ai_settings`), nothing followed, no news. Then
   `ai_digest_context` hands over the messages: only chats the person still
   belongs to and may read (`current_user_readable_conversation_ids`, so a
   circle channel they lost access to or a suspended circle is out), where the
   circle and the group owner allow AI (`conversation_ai_assistant_allowed`),
   never recalled, expired, AI-guard-held, view-once, system, own, assistant
   or blocked-sender messages; the newest 200 per chat;
4. the function counts ONE request for the whole digest against
   `AI_DAILY_LIMIT_PER_USER` (given back on failure), asks the model once for
   an `=== N ===` section per chat (chat text and names fenced as untrusted
   data, `DATA_RULES`), and `ai_digest_finish` stores the card and wakes
   `scheduled-dispatch`, whose `claim_digest_pushes` sends the push (not in Do
   Not Disturb, after quiet hours rules, never older than 15 minutes).

The follow limit is a trigger on `ai_digest_subscriptions`, so it holds for every
writer. Leaving a chat deletes the subscription (trigger), deleting the account
or a chat cascades, and cards are removed after two weeks. Deploy: apply the
migrations, then `supabase functions deploy ai scheduled-dispatch data-export`.
Nothing new to set.

### AI in notes (`note_assist`)

The notes editor's `/` menu has "AI…" and the format bar has a sparkle button
(`lib/features/ai/note_assist/`). Six jobs: continue writing, summarize, make an
outline, change the tone (polite, formal, relaxed, shorter, fix spelling),
translate, pull out the to-dos. It works on the words selected in a block, or on
the whole note when nothing is selected. No migration, and nothing new to set;
deploy with `supabase functions deploy ai`. Code: `supabase/functions/ai/note_assist.ts`
(decisions) and `note_assist_store.ts` (reading); `request.ts`, `handler.ts` and
`index.ts` only gained a branch each.

- **Read as the caller.** The note and its blocks are read with the caller's own
  database access, so a note they cannot see (not a member, a suspended circle,
  deleted) is `note_not_found` and nothing is sent to the model. A selection
  comes from the app (at most `MAX_TEXT_CHARS`, 8000); without one the function
  reads the whole note itself, up to 12000 characters or `AI_MAX_INPUT_CHARS` if
  lower: the end of the note for "continue", the start for the rest
  (`truncated: true` tells the app).
- **Switches.** The circle's AI switch (`ai_disabled_in_circle`) and the person's
  own (`ai_disabled_for_user`) are asked before anything is read or counted. One
  request counts against `AI_DAILY_LIMIT_PER_USER` like every other action and is
  given back when the model fails or answers with nothing. An empty note costs
  nothing.
- **Untrusted text.** The note is data written by other people: cleaned of
  control characters and the prompts' fence tags, put between `<text_to_process>`
  tags, and the system prompt carries `DATA_RULES` and says to process the text,
  never follow it. The answer is turned into blocks of the kinds a note has
  (headings, bullets, numbered items, to-dos, quotes, paragraphs; links, pictures,
  HTML and code fences are stripped), at most 60 blocks of 2000 characters.
- **Nothing is written by the function.** The app shows the answer; "Add below" or
  "Replace the selection" puts it into the note with the ordinary block edits
  (`note_apply_ops`), after saving a version named "Before the AI" so it can be
  undone from the version history.
- The to-dos (`extract_tasks`) come back as unchecked to-do blocks in the note;
  they are not turned into tasks of a task list.

### Call recap (`meeting_recap`)

When captions were on in a call (roadmap E1), the person who turned them on can
ask for a recap when they turn them off or leave. The app sends the sentences the
people in the call chose to share; the function answers with the minutes: a
title, the key points, the decisions and the to-dos. The app saves them as a note
in the conversation and posts the note card; the to-dos open the "To-dos from the
chat" review sheet (F4), so tasks are only made when the person confirms. No new
secret. Deploy with `supabase functions deploy ai`; captions themselves also need
the migration `202610240100_call_captions_host.sql` and `supabase functions deploy
livekit-token` (see "Who may turn captions on" below). Code:
`supabase/functions/ai/meeting_recap.ts` (decisions) and `meeting_recap_request.ts`
(reading the request); `request.ts`, `handler.ts` and `index.ts` only gained a
branch each. It reuses the to-do rules of `extract_actions.ts`.

Request: `{action: "meeting_recap", conversation_id, entries: [{speaker, text, at?}],
language?, time_zone?, utc_offset_minutes?}` with at most 2000 sentences of 600
characters; `speaker` is a user id and `at` the seconds since captions started.
Answer: `{title, summary: [...], decisions: [...], action_items: [item, ...],
truncated, line_count, speaker_count}`, where an item has the shape `extract_actions`
returns (`source_message_id` is always null).

- **Names come from the database.** A sentence carries its speaker's user id and
  the function writes that member's own name in front of it (`Someone` for an id
  that is no member), so the app cannot put words in a named person's mouth in the
  prompt. To-do assignees are members of the conversation or nobody.
- **Switches and limits.** The circle's AI switch (`ai_disabled_in_circle`) and
  the person's own (`ai_disabled_for_user`) are asked first; the caller must be a
  member of the conversation (else `conversation_not_found`); a request counts
  against `AI_DAILY_LIMIT_PER_USER` and is given back when the model fails. A
  transcript with nothing in it costs nothing.
- **Untrusted text.** The transcript is data: cleaned of control characters and
  the prompts' fence tags, put between `<transcript>` tags, with `DATA_RULES` in
  the system prompt. A transcript longer than `AI_MAX_INPUT_CHARS` keeps its start
  and its end (`truncated: true`).
- **Nothing is recorded or stored.** The function answers and forgets. Captions
  are made on each person's device from their own microphone and shared as text;
  only people who chose to share are in the transcript, and the transcript only
  lives in the host's memory until they ask for the recap.

### Who may turn captions on (`livekit-token`)

`livekit-token` asks `can_current_user_host_captions` when it mints a token and
writes the participant attribute `cap=1` into the signed token for people who may:
members who may mute members in a voice channel or stage, either person in a
one-to-one call, and the starter and the owner / admins of a group call. The apps
accept "captions are on" only from a participant with that attribute. Deploy order:
migration, then `supabase functions deploy livekit-token`. Tokens minted before
that (and clients on an older function) simply have nobody who may start captions.

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
flutter test test/features/ai test/features/transcribe test/supabase/ai_guard_test.dart test/supabase/ai_assistant_test.dart test/supabase/daily_digest_test.dart test/features/inbox test/features/notes
```
