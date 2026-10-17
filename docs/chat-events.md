# Events in chats and their reminders

Group chats and direct messages can post an event (title, time, place or
link, description). It appears in the chat as a card with Going / Maybe /
Can't buttons, can be pinned under the chat header, and reminds the people
who answered Going or Maybe 15 minutes and/or 1 hour before it starts. Circles
keep their own events (`circle_events`).

Migration: `supabase/migrations/202610170050_chat_events.sql`.
Client: `lib/features/chats/events/`, `lib/shared/models/chat_event.dart`.

## Tables and RPCs

| | |
| --- | --- |
| `chat_events` | the events; `reminder_leads` is a subset of `{15, 60}` (minutes) |
| `chat_event_rsvps` | `going`, `maybe` or `declined` per member |
| `chat_event_reminders` | one row per person and due reminder: the inbox entry (`read_at`) and the push claim (`push_sent_at`) |
| `create_chat_event`, `update_chat_event`, `cancel_chat_event`, `rsvp_chat_event`, `pin_chat_event` | the only writers; they post / update the announcing system message (`attachment = {kind: 'event', event_id}`) |
| `get_chat_event`, `list_chat_events` | read an event or a chat's events |
| `list_chat_event_reminders`, `mark_chat_event_reminders_read` | the inbox's "Starting soon" cards |

## Reminders: what the scheduler has to call

Two functions, both for postgres / the service role only, both safe to run
as often as you like (every minute is right):

```sql
select public.chat_event_due_reminders();             -- writes the inbox rows; returns how many are new
select * from public.claim_chat_event_reminder_pushes();  -- Web Push work, each reminder handed out once
```

* `chat_event_due_reminders(as_of => now())` finds events whose reminder
  time has come (`starts_at - lead <= as_of < starts_at`) and inserts one
  `chat_event_reminders` row for each person who is Going or Maybe and still
  in the chat. For a person it picks the most imminent open reminder, so
  someone who answers 10 minutes before gets the 15-minute one only.
  Moving an event (`update_chat_event`) deletes its reminders so they fire
  again; cancelled events never remind.
* `claim_chat_event_reminder_pushes()` marks undelivered reminders (created in
  the last 30 minutes) as pushed and returns one row per device
  (`endpoint`, `p256dh`, `auth`, `title`, `body`, `conversation_id`),
  skipping chats the person muted.

### What is scheduled by the migration

If `pg_cron` is installed the migration schedules
`chat-event-due-reminders` (`* * * * *`, only the first function, so the
inbox works with nothing else) and a daily purge of reminders older than 14
days. On a database without `pg_cron` (local development) it schedules
nothing.

### Push

`supabase/functions/chat-event-reminders` (verify_jwt = false, shared secret)
calls both functions and sends the pushes with `push/webpush.ts`. Invoke it
every minute from the same scheduler as the SQL function:

```sql
select cron.schedule('chat-event-reminders', '* * * * *', $$
  select net.http_post(
    url := 'https://<project>.supabase.co/functions/v1/chat-event-reminders',
    headers := jsonb_build_object('Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'))
  )
$$);
```

### Merging with the shared dispatcher

The scheduled-message / reminder dispatcher that runs from `pg_cron` only
needs to add these two calls to its tick:

1. `perform public.chat_event_due_reminders();`
2. send the rows of `public.claim_chat_event_reminder_pushes()` the way it
   sends other pushes (or POST to `chat-event-reminders`).

Drop the job `chat-event-due-reminders` once the dispatcher calls it.
Nothing else depends on the job names.

## Deploying

1. Apply the migration.
2. `supabase functions deploy chat-event-reminders` and set the usual VAPID
   secrets (shared with `push`).
