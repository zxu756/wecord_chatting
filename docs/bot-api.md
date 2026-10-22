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

With `components` the message has buttons, links and lists, see
[Buttons, links and lists](#buttons-links-and-lists).

### Change your own message

`PATCH /messages/{id}` changes the text and/or the components of a message
the bot sent (not someone else's, not a deleted one). `"components": null`
or `[]` takes them off. The text goes through the same rules as anyone's edit
(edit history, AutoMod, the circle's edit time limit); changing only the
components touches none of them. Answers `200 {"id": "…"}`.

```sh
curl -X PATCH -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" \
  -d '{"content":"Approved by Ann","components":[]}' \
  "$BASE/messages/$MESSAGE_ID"
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

A bot needs no public URL: it **polls** for interactions. (A bot with a
server can instead ask for a signed [callback](#callbacks).) A poll hands out
up to `limit` (1 to 100, default 25) unanswered interactions; one that is not
answered within 30 seconds is handed out again by a later poll. Interactions
expire after 15 minutes. Every item says what it is in `type`: `"command"` (a
slash command) or `"component"` (a press on a button or list, see
[Buttons, links and lists](#buttons-links-and-lists)).

```sh
curl -H "Authorization: Bot $TOKEN" "$BASE/interactions"
# [{"id":"…","type":"command","command":"ping","options":"now please",
#   "channel_id":"…","user":{"id":"…","username":"ann","name":"Ann"},
#   "created_at":"…","expires_at":"…"}]
```

Answer each interaction once; the answer is posted in the channel and
shown under "Ann used /ping". Answers `201 {"id": "<message id>"}`. The
body can also carry `components` and a `type` (see
[Answering a press](#answering-a-press)).

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

## Buttons, links and lists

A message can carry up to **5 rows of up to 5 components** (25 in all, 8 KB
at most). A row is a list; a drop-down list takes a whole row.

```sh
curl -X POST -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "content": "The **budget** is ready for review.",
    "components": [
      [
        {"type": "button", "id": "approve", "label": "Approve", "style": "primary"},
        {"type": "button", "id": "reject", "label": "Reject", "style": "danger"},
        {"type": "link", "label": "Open the sheet", "url": "https://example.com/budget"}
      ],
      [
        {"type": "select", "id": "owner", "placeholder": "Who takes it?",
         "options": [
           {"label": "Ann", "value": "ann", "description": "Finance"},
           {"label": "Bo", "value": "bo"}
         ], "min_values": 1, "max_values": 1}
      ],
      [
        {"type": "button", "id": "note", "label": "Add a note",
         "modal": {"title": "Your note", "fields": [
           {"id": "text", "label": "Note", "style": "paragraph", "max_length": 300},
           {"id": "name", "label": "Name", "required": false}
         ]}}
      ]
    ]
  }' \
  "$BASE/channels/$CHANNEL_ID/messages"
```

| Component | Fields |
| --- | --- |
| `button` | `id`, `label` (1 to 40 characters), `style` (`primary`, `secondary` (default) or `danger`), `disabled`, `modal` (a form to fill before the press is sent) |
| `link` | `label`, `url`: **https only**, a website name (no IP address, no `localhost`, no `.local`/`.internal` names, no other port, no user name or password, no spaces or quotes), up to 500 characters. The app asks "Open this link?" and shows the address before opening it. A link has no `id` and sends nothing to you |
| `select` | `id`, `placeholder` (up to 100), `options` (1 to 25 of `label` up to 100, `value` up to 100 and unique, `description` up to 100, `default`), `min_values` (default 1), `max_values` (default 1, at most the number of options), `disabled` |
| form (`modal` of a button) | `title` (up to 45), `fields` (1 to 5 of `id`, `label` up to 45, `style` `short` or `paragraph`, `required` (default true), `placeholder`, `max_length` 1 to 1000, default 200) |

Ids are 1 to 64 of letters, digits and `_ . : -`, and different within a
message. Texts are plain text everywhere (no markdown or HTML), without
control characters, new lines or characters that change the text direction;
unknown keys are dropped. AutoMod reads the texts of the buttons and options
like the message itself (a blocked one stops the message quietly, `403
blocked`). Components belong to the bot's own text messages only; a bot can
not put them on anything that looks like a system line.

Anyone who can see the message can press a component (the server checks that
for every press), at most 30 presses a minute per person and one a second per
component. A press arrives as an interaction of `type` `"component"`:

```json
{"id": "…", "type": "component", "channel_id": "…",
 "message_id": "…", "ephemeral": false,
 "component": {"id": "owner", "type": "select", "label": "Who takes it?"},
 "values": ["ann"],
 "user": {"id": "…", "username": "ann", "name": "Ann"},
 "created_at": "…", "expires_at": "…"}
```

`values` is `null` for a button, the chosen option values for a list and an
object of field id to text for a form (`component.type` is `"modal"`).
`message_id` is the message that was pressed on, also when the press was on a
private reply (`ephemeral: true`). A bot with 200 unanswered presses is told
to wait (people get "This bot is busy").

## Answering a press

`POST /interactions/{id}/respond` takes `{"type"?, "content"?, "components"?}`;
one answer per interaction (`409` after that), within the 15 minutes it
stands. People see "Sent to Bot, waiting for an answer…" for up to 10 seconds
and then "Bot did not answer", so answer fast (an `ack` is enough).

| `type` | What happens | Needs | Answers |
| --- | --- | --- | --- |
| `message` (default) | A message in the channel, with "Ann pressed Approve" above it | `content` | `201 {"id"}` |
| `ephemeral` | A **private reply**, seen only by the person who pressed, under the message they pressed on; kept for a day, at most 20 per person and chat, they can dismiss it. Not a message: no push, no unread, no history. It can have its own `components` (pressing them reaches you with `ephemeral: true`) | `content` | `201 {"id"}` |
| `update` | Changes the message that was pressed on (its text and/or `components`; `"components": []` takes them off), or the private reply if the press was on one | `content` and/or `components` | `200 {"id"}` |
| `ack` | Nothing visible; the press is marked answered | nothing | `200 {"ok": true}` |

A slash command can only be answered with a `message` (which may carry
`components`).

```sh
curl -X POST -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"update","content":"Approved by Ann","components":[]}' \
  "$BASE/interactions/$INTERACTION_ID/respond"
```

## Callbacks

Instead of polling, a circle manager can give a bot a **callback address**
(Circle settings → Bots → the bot → Callback address). Every interaction (slash
command or press) is then POSTed to it as it happens, as JSON:

```json
{"version": 1, "type": "interaction", "bot_id": "…", "circle_id": "…",
 "attempt": 1,
 "interaction": {"id": "…", "type": "component", "…": "as in a poll"}}
```

You still answer through the API with your token (`/interactions/{id}/respond`).
A callback that is set is used instead of polling, so a poll does not hand out
those interactions again, unless the delivery failed for good.

**Check every request.** The headers are:

- `X-WeCord-Timestamp`: seconds since 1970 when it was sent;
- `X-WeCord-Signature`: `v1=` and the hex HMAC-SHA256 of `"<timestamp>.<body>"`
  (the raw body as received) with the callback secret as the key;
- `X-WeCord-Delivery`: the interaction id.

Compare the signature in constant time, reject a timestamp more than five
minutes from your clock and remember the delivery ids you have seen for that
long (a delivery can come twice). The secret is shown **once**, when the
address is set (and when it is reset); WeCord keeps it to sign with and never
shows it again.

```js
import { createHmac, timingSafeEqual } from "node:crypto";

function verify(secret, headers, rawBody) {
  const timestamp = Number(headers["x-wecord-timestamp"]);
  if (!Number.isFinite(timestamp) || Math.abs(Date.now() / 1000 - timestamp) > 300) return false;
  const expected = "v1=" + createHmac("sha256", secret).update(`${timestamp}.${rawBody}`).digest("hex");
  const given = headers["x-wecord-signature"] ?? "";
  return given.length === expected.length &&
    timingSafeEqual(Buffer.from(given), Buffer.from(expected));
}
```

Rules of the sender: the address must be `https://` with a real website name on
the usual port (the server refuses IP addresses, `localhost`, `.local`,
`.internal`, `.lan`, other ports, user names and passwords, and names that point
at inner addresses); before every send the name is looked up and **every**
address it has must be a public one (loopback, private, link-local, shared,
documentation, multicast and reserved ranges are refused, IPv4 and IPv6);
redirects are not followed; the timeout is 5 seconds; any `2xx` counts as
delivered and the body of your answer is ignored. A failed delivery is tried
again after 5 seconds, 30 seconds and 2 minutes (four tries in all), then the
interaction goes back to polling. After 20 interactions in a row lost for good
the callback is paused (the managers see why and saving the address again turns
it on); you can always poll meanwhile. Setting, resetting and removing a
callback is in the circle's audit log.

## Errors and limits

Errors are JSON `{"error": "…", "message": "…"}`:

| Status | Meaning |
| --- | --- |
| 400 | Invalid body or query (`content_required`, `invalid_command_name`, …) |
| 401 | Missing, malformed, unknown or revoked token |
| 403 | The bot is not allowed (missing permission, timed out, removed from the circle), or the circle's AutoMod blocked the message or its buttons (`blocked`) |
| 404 | Unknown endpoint, or a channel / message / interaction the bot cannot see |
| 405 | Wrong method for the endpoint |
| 409 | Command name taken in the circle, or interaction already answered |
| 413 | Body over 32 KB |
| 429 | More than 60 writes per minute (`rate_limited`), or channel slowmode (`slowmode`) |

Writes are sending messages, changing them, reacting, setting commands and
answering interactions. A refused component comes back as `400
invalid_request` with the reason in `message`.

## Deploying

The function is public (`verify_jwt = false` in `supabase/config.toml`);
it checks the token itself through the `bot_api_*` database functions,
which only the service role may call. Deploy it with
`supabase functions deploy bot-api` after pushing the migrations
(`202610160030_bot_api.sql`, and `202610280610`-`202610280660` for components,
private replies and callbacks).

Callbacks are sent by the `bot-callbacks` function, which is called only by
the database with the shared secret `DISPATCH_SECRET` as the bearer token
(`verify_jwt = false`, like `scheduled-dispatch`). Deploy it with
`supabase functions deploy bot-callbacks`; it needs the same Vault secrets
(`wecord_functions_url`, `wecord_dispatch_secret`) as the other woken functions.
