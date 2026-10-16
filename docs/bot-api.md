# WeCord bot API

A bot is a member account of one circle that a program controls over
HTTP. Members with the Manage circle permission create bots in **Circle
settings → Bots**, optionally
with a role; the bot then has exactly the permissions of a member with
that role (channel overwrites, timeouts and slowmode included). The token
is shown once; managers can reset it (the old one stops working), revoke
it (the bot stops working until reset) or delete the bot (it leaves the
circle and its login is deleted; its messages stay).

The API is the `bot-api` Edge Function:

```
BASE=https://<project>.supabase.co/functions/v1/bot-api
TOKEN=<the bot token>
```

Every request sends `Authorization: Bot $TOKEN`. Bodies are JSON
(`Content-Type: application/json`, at most 32 KB).

## Endpoints

### Who am I

```sh
curl -H "Authorization: Bot $TOKEN" "$BASE/me"
# {"id":"…","user_id":"…","name":"Helper","circle_id":"…","circle_name":"Study Hall"}
```

### Channels the bot can see

```sh
curl -H "Authorization: Bot $TOKEN" "$BASE/channels"
# [{"id":"…","name":"general","kind":"text","topic":null,"category_id":null,
#   "category_name":null,"position":0,"can_send":true}, …]
```

### Recent messages of a channel

Newest first; `limit` 1 to 100 (default 50), `before` an ISO time for
older pages.

```sh
curl -H "Authorization: Bot $TOKEN" \
  "$BASE/channels/$CHANNEL_ID/messages?limit=20"
# [{"id":"…","channel_id":"…","type":"text","content":"hi","deleted":false,
#   "created_at":"…","edited_at":null,"reply_to_message_id":null,
#   "author":{"id":"…","username":"ann","name":"Ann","is_bot":false},
#   "interaction":null}, …]
```

### Send a message

`content` is 1 to 2000 characters of the usual message markdown;
`reply_to` optionally names a message of the same channel. Answers
`201 {"id": "<message id>"}`.

```sh
curl -X POST -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" \
  -d '{"content":"Build **passed**","reply_to":"<message id>"}' \
  "$BASE/channels/$CHANNEL_ID/messages"
```

### Add a reaction

The emoji is URL-encoded in the path (`custom:<id>` for a circle emoji).
Reacting twice with the same emoji does nothing. Answers `204`.

```sh
curl -X PUT -H "Authorization: Bot $TOKEN" \
  "$BASE/messages/$MESSAGE_ID/reactions/%F0%9F%91%8D"
```

### Slash commands

A bot registers up to 25 commands (`name`: a-z, 0-9, `_` or `-`, up to 32;
`description`: up to 100 characters). Names are unique within the circle,
and the built-in commands (`/shrug`, `/me`, …) always win. `PUT` replaces
the whole list.

```sh
curl -X PUT -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" \
  -d '[{"name":"ping","description":"Replies with pong"}]' \
  "$BASE/commands"
curl -H "Authorization: Bot $TOKEN" "$BASE/commands"
```

Members see the commands in the composer of the circle's channels. Typing
`/ping now please` and sending it does not post a message: it records an
**interaction** for the bot (the member needs to be able to send messages
there, and the bot must see and post in the channel).

Bots **poll** for interactions; there are no outgoing webhooks, so a bot
needs no public URL. A poll hands out up to `limit` (1 to 100, default 25)
unanswered interactions; one that is not answered within 30 seconds is
handed out again by a later poll. Interactions expire after 15 minutes.

```sh
curl -H "Authorization: Bot $TOKEN" "$BASE/interactions"
# [{"id":"…","command":"ping","options":"now please","channel_id":"…",
#   "user":{"id":"…","username":"ann","name":"Ann"},
#   "created_at":"…","expires_at":"…"}]
```

Answer each interaction once; the answer is posted in the channel and
shown under "Ann used /ping". Answers `201 {"id": "<message id>"}`.

```sh
curl -X POST -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" \
  -d '{"content":"pong"}' \
  "$BASE/interactions/$INTERACTION_ID/respond"
```

A minimal loop:

```sh
while true; do
  curl -s -H "Authorization: Bot $TOKEN" "$BASE/interactions" |
    jq -r '.[].id' | while read -r id; do
      curl -s -X POST -H "Authorization: Bot $TOKEN" \
        -H "Content-Type: application/json" -d '{"content":"pong"}' \
        "$BASE/interactions/$id/respond" > /dev/null
    done
  sleep 2
done
```

## Errors and limits

Errors are JSON `{"error": "…", "message": "…"}`:

| Status | Meaning |
| --- | --- |
| 400 | Invalid body or query (`content_required`, `invalid_command_name`, …) |
| 401 | Missing, malformed, unknown or revoked token |
| 403 | The bot is not allowed (missing permission, timed out, removed from the circle), or the circle's AutoMod blocked the message (`blocked`) |
| 404 | Unknown endpoint, or a channel / message / interaction the bot cannot see |
| 405 | Wrong method for the endpoint |
| 409 | Command name taken in the circle, or interaction already answered |
| 413 | Body over 32 KB |
| 429 | More than 60 writes per minute (`rate_limited`), or channel slowmode (`slowmode`) |

Writes are sending messages, reacting, setting commands and answering
interactions.

## Deploying

The function is public (`verify_jwt = false` in `supabase/config.toml`);
it checks the token itself through the `bot_api_*` database functions,
which only the service role may call. Deploy it with
`supabase functions deploy bot-api` after pushing migration
`202610160030_bot_api.sql`.
