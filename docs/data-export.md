# Download my data

Settings -> Privacy & Safety -> Download my data. The `data-export` Edge
Function collects what WeCord keeps about the caller into a ZIP, stores it
in a private bucket and hands out a signed link.

Migrations: `supabase/migrations/202610170053_data_export.sql` (bucket, table,
rate limit) and `supabase/migrations/202610190023_data_export_more.sql`
(Moments, chains, notes and the rest, below).
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

### Moments, chains, notes and the rest

```
pages/moments.html           Moments, friend tags and starred friends
pages/chains.html            group chains
pages/notes.html             notes and task lists
pages/saved.html             saved messages, reminders, scheduled messages
pages/favorites.html         favorites: folders, tags, links, notes (data/favorites.json)
pages/wallpapers.html        chat wallpapers
data/moments.json            settings, friend_choices, posts, comments_you_wrote, posts_you_liked
data/moments_more.json       pinned_posts, reminded_by_you, reminded_you, comment_pictures (links)
data/knowledge.json         pages_made, pages_read (circle knowledge base)
data/honors.json            titles, honors, streaks, opted_out (circle titles and honors)
data/channel_posts.json     media_posts, questions, accepted_answers (media and Q&A channels)
data/events.json            signed_up, waiting, check_ins, photos, events_made (events 2.0)
data/group_space.json       albums, items, folders, files (albums and folders of group chats)
data/friend_tags.json        tags (with who is in them), starred_friends
data/chains.json  data/notes.json  data/task_lists.json
data/saved_messages.json  data/reminders.json  data/scheduled_messages.json
data/wallpapers.json
files/moments/…  files/wallpapers/…   your own photos, videos, cover and wallpaper photos
```

The rule for all of it: **only content you wrote or own**. Other people appear
by name only (id, username, display name: the names the export already
carries for friends and chats). The database functions
`export_my_moments(user)` and `export_my_extras(user)` (SECURITY DEFINER,
service role only, each starting from the user they are given) read it, and
`test/supabase/data_export_behaviour.sql` proves, in a rolled-back
transaction, that another person's Moments, chain lines, notes, lists,
saved messages, reminders, scheduled messages and wallpapers do not come out.
The rule per section:

| Section | What is exported | What is not |
| --- | --- | --- |
| Moments settings | visible range, cover file you own | |
| Per-friend choices | your hide_mine / hide_theirs, friend named | the friend's own choices |
| Your posts | every column of posts you wrote (text, link, place, visibility, photos, a `video` if that column exists), the audience resolved to names and tag names | other people's posts, photos, tags |
| Comments you wrote | your text, the post id, the post author's name, who you replied to by name; the post's text only if the post is yours | the rest of the thread, other people's comments, comment counts |
| Likes | post id and time | who else liked, the post |
| Circle knowledge base | the pages you made (with their circle) and the pages you opened; a title only while you can still read the page; `data/knowledge.json` and `pages/knowledge.html` (migration 202610270130, `export_my_knowledge`; the words you wrote are in `data/notes.json`) | other people's pages and words |
| Circle titles and honors | the titles circles gave you (with the circle), the honors you earned (a week's level or a streak milestone, with its date), your running streak and best streak per circle, and the circles where you chose to stay out of honors; `data/honors.json` and `pages/honors.html` (migration 202610270240, `export_my_honors`) | other members' titles, honors or numbers, and the days you were active (the C3 table is not exported) |
| Picture posts and Q&A | the posts you made in media channels (circle, channel, title, time, a link to the picture and the description you wrote), the questions you asked in Q&A channels (solved or not, when, whether an answer was accepted, whether you marked it yourself) and where an answer of yours was accepted (circle, channel and time only); `data/channel_posts.json` and `pages/channel_posts.html` (migration 202610270330, `export_my_channel_posts`; the words you wrote are with your messages) | other people's posts, questions, answers and the titles of questions you did not ask |
| Events 2.0 | the events you signed up to (circle or chat, while you still belong) with the answers you gave to their questions, the waiting lists you are on, where you checked in, the pictures you added (links), and the events you made with their settings (repeat and its zone, seats, the questions asked, cover); `data/events.json` and `pages/events.html` (migration 202610270470, `export_my_events2`) | other people's answers, names and pictures |
| Group space (albums and folders) | the albums and folders you made in group chats (name, the group's title while you are still in it, time) and the pictures, videos and files you added (name, size, the description you wrote, a link, the album or folder); `data/group_space.json` and `pages/group_space.html` (migration 202610280230, `export_my_group_space`) | what other members put in the same albums and folders, and their names |
| Moments 2.0 (pins, reminders, comment pictures) | which of your posts are pinned and when, the people you reminded to read each post (names), the reminders you got (who and when, never their words), the pictures on the comments you wrote with their descriptions as links, and the descriptions of your own photos; `data/moments_more.json` and extra lines on `pages/moments.html` (migration 202610260650, `export_my_moments_more`) | what others wrote in reminders, others' posts and pictures |
| Friend tags | your tags and who is in them (names) | anyone else's tags |
| Starred friends | your stars (names) | anyone else's stars |
| Group chains | chains you started or joined: title, creator's name, deadline, cap, entry count, state, **your own line**; the description and example only for chains you started | other people's lines, who else joined |
| Forms | forms you made (title, description, questions, settings, number of answers) or answered (title, questions, **your own answers**, with pictures you attached as links); `pages/forms.html`, `data/forms.json` (migration 202610230130, `export_my_forms`) | other people's answers, who answered a form you made (never for anonymous forms) |
| Daily digest | whether it is on, the time, language and time zone, and the chats you follow (names only); `pages/ai_digest.html`, `data/ai_digest.json` (migration 202610230540, `export_my_ai_digest`) | the digests themselves (two-week summaries of other people's messages) |
| Daily (24-hour dailies) | the dailies you still have up (caption, audience as a word, how many people viewed, links to the photo, poster and thumbnail), your close friends (names) and the dailies you reported; `pages/stories.html`, `data/stories.json` (migration 202610240250, `export_my_stories`). A daily is gone 24 hours after posting, so only live ones are here | who viewed or reacted to a daily, other people's dailies, the replies (they are chat messages and are in the chats) |
| Notes | notes you made or wrote in (not deleted): title, icon, chat name; only the blocks whose **last editor is you** | blocks last edited by others (so a note you made may be incomplete if others changed lines), notes in chats you never wrote in, deleted notes, version history |
| Task lists | lists you made or added items to (not deleted): title, chat name; only items **you created**, with who they are assigned to by name | items others created, items assigned to you by others, deleted items |
| Saved messages | when and where you saved; the text only if you wrote the message | the text of other people's messages |
| Favorites (folders, tags, kept Moments, posts, links, notes) | folders, tags, remarks, your links and notes whole (with links to note pictures); the words of a message, Moment or post only if you wrote it | other people's words |
| Reminders | when and where; the text only if you wrote the message | the text of other people's messages |
| Scheduled messages | everything you scheduled (text, time, status) | |
| Wallpapers | your choice per chat or default, wallpaper photo you own | |

Chat names come from the conversations list; a chat you have left shows as
"A conversation you left". Images inside notes are not exported (only their
text blocks).

Files from Storage (`moments`, `wallpapers` buckets) are limited to your own
folder (`<your id>/…`, checked in the function whatever the database says).
They are put into the ZIP itself while they fit: each file up to 10 MB, 40 MB
and 500 files in all, and up to 90 seconds of downloading (constants in
`collect.ts`); a video of unknown size is never downloaded, it is linked. A
file that does not fit, or cannot be read, gets a signed link in the JSON and
pages that works as long as the export (7 days). Rows are capped per section
inside the SQL functions (for example 5,000 posts, 10,000 comments) so one
export stays small.

## Flow

1. `POST /functions/v1/data-export` starts an export and answers `202 {id}`;
   the work continues after the answer (`EdgeRuntime.waitUntil`).
   `429 rate_limited {retry_after_seconds}` when the last export was less than
   24 hours ago, `409 in_progress {id}` while one is running. The check is
   `begin_data_export(user)`, which also inserts the `data_exports` row under
   an advisory lock.
2. The function updates the row's `stage` and `progress` (queued, profile,
   friends, conversations, messages, circles, moments, more, attachments, packaging,
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

1. Apply the migrations (the first creates the bucket, `data_exports`,
   policies and `begin_data_export`; `202610190023` adds `export_my_moments`,
   `export_my_extras` and `export_person_json`, service role only). The
   second needs the Moments, friend tags, chains, notes, task lists, saved
   messages, reminders, scheduled messages and wallpapers migrations before it.
2. `supabase functions deploy data-export`. Deploy the migration first: an
   export made before it lists "moments" and "notes, lists and more" under
   "Not included" instead of failing.
