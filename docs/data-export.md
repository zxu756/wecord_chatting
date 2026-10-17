# Download my data

Settings -> Privacy & Safety -> Download my data. The `data-export` Edge
Function collects what WeCord keeps about the caller into a ZIP, stores it
in a private bucket and hands out a signed link.

Migration: `supabase/migrations/202610170053_data_export.sql`.
Function: `supabase/functions/data-export/` (verify_jwt = true).
Client: `lib/features/settings/data_export.dart`.

## What is in the ZIP

```
index.html              readable overview with a page per conversation
messages/<chat>.html    the messages you sent in that conversation
data/profile.json       account (email, created) and profile
data/settings.json      privacy and notification settings
data/friends.json       friends (with your remarks), friend requests, blocked users
data/conversations.json the conversations you are in: names only
data/messages.json      every message you sent: text, times, links to files
data/circles.json       circles you belong to, nickname, notification level
README.txt
```

Only the caller's own rows are read (always filtered by their id, with the
service role). Other people's messages are not included, only the names of
the chats. Files in messages are linked with signed URLs that last as long as
the export (7 days). A part that cannot be read (a table a deployment lacks)
is listed under "Not included" in `index.html` instead of failing the export.

## Flow

1. `POST /functions/v1/data-export` starts an export and answers `202 {id}`;
   the work continues after the answer (`EdgeRuntime.waitUntil`).
   `429 rate_limited {retry_after_seconds}` when the last export was less than
   24 hours ago, `409 in_progress {id}` while one is running. The check is
   `begin_data_export(user)`, which also inserts the `data_exports` row under
   an advisory lock.
2. The function updates the row's `stage` and `progress` (queued, profile,
   friends, conversations, messages, circles, attachments, packaging,
   uploading, ready). The app polls `GET /functions/v1/data-export?id=<id>`
   every 1.5 seconds for the progress bar.
3. The ZIP is uploaded to `data-exports/<user id>/<timestamp>.zip`. Only the
   owner can read that folder (storage policy); nobody can write through the
   API. A ready export's `GET` answer carries `download_url`, a signed link
   valid for an hour (ask again for a fresh one until the export expires).

## Deleting old exports

An export expires 7 days after it was made. Files are removed:

* whenever anyone starts an export (the function purges every expired file and
  keeps only the newest export of that person), and
* optionally from a scheduler: `POST /functions/v1/data-export` with the
  service role key as bearer and body `{"purge": true}`:

```sql
select cron.schedule('data-export-purge', '23 4 * * *', $$
  select net.http_post(
    url := 'https://<project>.supabase.co/functions/v1/data-export',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body := '{"purge": true}'::jsonb
  )
$$);
```

## Deploying

1. Apply the migration (creates the bucket, `data_exports`, policies and
   `begin_data_export`).
2. `supabase functions deploy data-export`.
