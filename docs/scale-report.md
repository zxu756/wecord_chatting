# Scale report: big groups and big circles (roadmap L6)

What was tested, what was slow, what was changed, and what is still slow.
Everything was measured on the **local** database only (Postgres 17 from
`supabase start`), inside transactions that are rolled back. Nothing was run
against the hosted project.

Migrations: `202610281200_l6_hot_queries.sql`, `202610281210_l6_member_pages.sql`,
`202610281220_l6_push_pages.sql`. Scripts: `tool/scale/`.

## What was tested

| | full run | small run (to check the scripts) |
|---|---|---|
| people | 10 000 | 1 500 |
| group "Big group" | 5 000 members, 150 000 messages | 800 members, 8 000 messages |
| circle | 10 000 members, 8 channels (one with permission overwrites), AI guard on for newcomers | 1 200 members, 3 channels |
| channel messages | 25 000 | 2 000 |
| small chats | 150 direct chats, 30 small groups | 20 and 5 |
| totals | 413 000 messages, 106 000 conversation members, 12 000 push subscriptions, 192 conversations | |

The roadmap asked for 1 million messages. 413 000 was enough to show every
scan that grows with the size of the data (a full run seeds in about 2
minutes); the plans below are the same at 1 M, only the numbers are bigger.

Measured as a person (`set role authenticated` with the JWT claims set, so
row-level security applies) or, for the push claim, as the table owner (the
Edge Function uses the service role):

- chat list (`list_conversation_summaries`, `get_conversation_summary`),
- message list (latest 50 and an older page, with the computed columns the
  app asks for), reactions, read markers,
- member lists (group members, circle detail, circle list),
- unread (mark read, membership checks),
- search (`search_messages`, the legacy and the advanced one),
- sending (big group, circle channel with 10 000 members, a newcomer held by
  the AI guard, a direct chat),
- the push claim (`claim_push_delivery`) for one message,
- adding a member.

`EXPLAIN (ANALYZE, BUFFERS)` and `pg_stat_statements` (per statement, including
the ones inside functions and triggers) showed where the time went
(`scale_profile.sql`, `EXTRA="-v plans=1"`).

## How to run it again

```sh
sh tool/scale/run_scale.sh small bench          # a quick check
sh tool/scale/run_scale.sh full before bench    # without the L6 migrations
sh tool/scale/run_scale.sh full after bench     # with them
sh tool/scale/run_scale.sh small equiv          # old and new functions answer the same
sh tool/scale/run_scale.sh full after tool/scale/scale_profile.sql
```

The local database must be at migration `202610170001`; the script applies the
migrations after it in a transaction, seeds, measures and rolls back. It takes
the advisory lock the behaviour tests take (`20261017`), so it waits for and
blocks other SQL tests while it runs. Do not run it while you are working
on something else: a full run uses a few hundred MB and about 3 minutes.

`equiv` is the proof that nothing changed for the caller: it seeds, keeps copies
of the old functions in a schema `l6old`, applies the L6 migrations and asks
both versions the same questions as six different people (a busy member, a
member with no read marks, a blocked pair, a chat with a deleted account,
the owner of the circle, a channel with permission overwrites): 164 comparisons,
0 differences. `test/supabase/scale_pages_behaviour.sql` (run by `flutter test`)
checks the new functions (pages, `member_limit`, push batches) with 51
assertions.

## Results (full run, milliseconds per call, median of 3-10 calls)

The machine was shared with other builds while these ran, so single numbers
move by up to 30 % between runs; the big differences are not noise.

| what | before | after |
|---|---|---|
| send a message, big group (5 000 members) | 64 | 2.9 |
| send a message, circle channel (10 000 members) | 133 | 2.4 |
| send a message, newcomer held by the AI guard | 124 | 4.9 |
| circle list (`list_circle_summaries`) | 337 | 8.3 |
| search, a rare word (`search_messages(text)`) | 75 | 2.8 |
| search, a common word | 94 | 60 |
| chat list, a busy member (180 chats, read marks) | 260 | 121 |
| chat list, a member who never read anything | 477 | 432 (see below) |
| one chat's summary, a member who never read the big group | 134 | 169 (noise; see below) |
| circle details, first 200 members (what the app asks now) | 417 (all 10 000) | 20 |
| a page of 100 circle members | not possible | 14 |
| a name search in the circle | not possible | 30 |
| a page of 100 group members | 189 (all 5 000, API cuts at 1 000) | 5.7 |
| an @-mention search ("scale user 4") | not possible | 2.6 |
| the latest 50 messages, big group | 5.7 | 9 (noise: 5.5-6.5 ms min both) |
| an older page of 50 messages | 1.7 | 2.1 |
| mark read, membership checks, reactions, read markers | < 1 | < 1 |
| the push claim, whole group, in one go (5 999 rows) | 125 to 430 | 120 to 235 |
| the push claim, circle channel, in one go (11 999 rows) | 360 to 1 230 | 380 to 700 |
| the push claim, in batches of 500 people | not possible | 40 to 145 per batch |

The two push lines are ranges over several runs: this call is the one most
disturbed by the other builds on the machine. In a batch the cost is the same
per person; the point of batches is that each call and each answer is bounded
(see below).

Sizes, not just times: `get_circle_detail` for 10 000 members was a 5 MB answer;
the first page of 200 is about 100 KB. A group of 5 000 read through the
REST API stopped at 1 000 rows (`max_rows`), so the app silently showed 1 000
members and the push never reached the rest.

## What was slow, and what changed

### Sending a message (the biggest finding)

Every send in a group runs the `messages` insert policy and `send_text_message`,
both of which call `is_current_user_blocked_in_conversation`. It joined **every
other member of the chat** and checked blocks for each one before looking at
whether the chat is a direct chat at all. In a group of 5 000 that was 60 ms or
more on every message, in a circle channel of 10 000 more than 120 ms.
It now looks at the type first, so a group or channel never touches the
member list (same answers; `equiv` covers blocks both ways and deleted
accounts). Sending is now 2-5 ms everywhere.

### Chat list

- `list_conversation_summaries` worked out the other person's profile, the
  member count and the mentions of **every chat in the database** and used the
  caller's. They are now restricted to the caller's chats.
- Unread counts read every message of a chat and threw away the old ones
  with a filter. The read marker is now a range
  (`created_at > last_read_at`) on the existing
  `messages_conversation_unread_idx (conversation_id, created_at desc)
  include (sender_id, attachment_group_id, webhook_name)`. The count is
  exactly the same (pats, hidden, expired and AI-held messages still do not
  count).
- `get_conversation_summary` computed the profile of all 5 000 members of a
  group it only needed the title of; now only for direct chats.

### Circle list

`list_circle_summaries` joined members x channels x posts to count distinct
rows. Each count is now its own subquery (8 ms instead of 340).

### Search

`search_messages(text)` read all memberships of the database to find the other
person of each direct chat; it now looks per direct chat.

### Members

- `get_circle_detail(circle, member_limit)` (new optional argument): the first
  `member_limit` members in the usual order (owner, admins, then by name) and
  always the caller, plus `circle.member_count`. Without the argument nothing
  changes. The app asks for 200.
- `list_circle_members_page` and `list_conversation_members_page`: a page after
  a cursor, or a name search. Same visibility as the detail and the
  `conversation_members` policy (members only; not a suspended circle; not people
  who cannot see a circle channel).
- Index `conversation_members_page_idx (conversation_id, joined_at, user_id)`.
- Client: the group sheet loads 100 and has "Show more members" and a search;
  the circle member panel loads the first 200 and has the same; typing `@` in a
  big group asks the database for matching names (8 at a time); the header says
  "5000 members" from the total.

### Push to a big group

`claim_push_delivery` returned one row per device of everyone who should
hear: 6 000 rows for the group, 12 000 for the channel. Two real bugs came
with that: the REST API cuts an answer at 1 000 rows, and the Edge Function
sent everything at once.

- The function takes an optional cursor and batch size
  (`claim_push_delivery(message, caller, after_user_id, page_size)`); the first
  call claims the message (so it is still pushed at most once), later calls only
  read on. Rows carry `recipient_id`, the cursor for the next call. The
  two-argument call still works (everyone).
- The recipient query keeps every check (muted, Do Not Disturb, blocks,
  channel visibility, circle notification levels, language of the text). The
  members come out of a sub-select with `offset 0` so the per-person checks
  (function calls) run on the people in turn and stop at the batch size,
  instead of on every member for every batch (this was found with EXPLAIN:
  the planner had picked a bitmap scan + sort, 10 batches cost 10 times the
  whole claim).
- Edge Functions: `push/claim_pages.ts` walks the batches (200 people each,
  guards against an answer cut at 1 000 rows, stops on errors keeping what
  went out); `push` handles each batch through the usual silent / quiet-hours /
  locked-chat / time-token steps and sends to at most 50 devices at the
  same time; `scheduled-dispatch` (scheduled messages, released AI-guard
  messages, away replies) uses the same helper.

## What is still slow (and why we left it)

1. **Unread count for a member who has never read a big chat.** 130-170 ms per
   chat, 430 ms for a chat list with such a chat in it: the count is exact, so
   it has to look at the 150 000 messages (a heap scan, because it checks
   review state, expiry, pats and the sender). A member with read marks (every
   normal case) takes 4 ms. Options if it ever matters: show `99+` and count
   at most 100 (a product decision and a client change, not a performance
   fix), or give a new member a read marker at the newest message when they
   join.
2. **The common-word search** (60 ms) is a full-text scan of the ranked matches
   over every readable conversation; the advanced search with its limit is
   14 ms. Fine at this size.
3. **Realtime.** Not changed, not measured (needs hosted Realtime):
   - The app's conversation list is already **one shared channel** for the
     user (messages, conversations, members, threads), so there is no "one
     channel per conversation" to merge. Chat pages open about 10 channels
     each while they are open and close them with the page; the limit is 100
     channels per connection, so a person would need ten chats open at once.
   - `postgres_changes` evaluates row-level security **for every subscriber of
     every change**. A message in a channel with 2 000 people online is 2 000
     policy evaluations on the database. This is the real ceiling for big
     circles and it is a Supabase plan matter (see below), not a query.
   - Presence (the "online" dots) is one presence channel; its fan-out is
     Realtime's, not the database's.
4. **Circle posts** (the legacy circle feed) are still returned whole by
   `get_circle_detail`; the app's big circles live in channels. Not changed.
5. **A few lists still hold only the first page** in a big group or circle:
   "Transfer ownership" candidates, the member picker for channel permission
   overwrites, "Invite friends" (it cannot hide the people already in), the
   forum post @ candidates, and the online count (hidden for big ones). Each
   works on the members that are loaded; the member list itself can load more.
6. **Mentions of `@everyone` / `@here`** in a big group were not measured on
   their own (the bench sends plain text). A mention writes one
   `message_mentions` row per recipient, and the push goes through the same
   batches as above; the profile of a plain send shows no mention work.
   Worth a run of its own before a 5 000-person group uses `@everyone` often.

## What needs a paid plan or a bigger machine

- **Supabase compute.** The local Postgres has the whole machine; the hosted
  free/small tier has 2 shared cores and 1 GB. Row-level-security checks
  (`is_current_user_conversation_member`, channel permission checks) are cheap
  per call (0.2 ms) but run per row and per Realtime subscriber. A circle with
  thousands of people online needs at least the Small/Medium compute add-on and
  watching the Realtime "messages per second" and "concurrent peak
  connections" limits (about 200 on free and 500 on Pro at the time of writing, more as add-ons).
- **Realtime connections and message rate.** Same page: the plan limits, not
  the code, decide how many people can be online in one circle at once.
- **Edge Function time.** One push to 5 000 people is about 30 batches; each
  batch is roughly 150 ms of database plus the time to contact 200 push
  services at 50 at a time. Supabase Edge Functions have a wall-clock limit
  (about 150 s on free and 400 s on paid; check the plan page); a 10 000-person channel is inside it, a
  100 000-person one would need the batches moved to a queue (`pg_cron` +
  `pg_net` per batch).
- **Database size.** 1 M messages with the search index is roughly 1 GB (estimated from the 413 000 seeded); the free
  plan has 500 MB.

## Notes for the next person

- Check `docs/scale-report.md` numbers with `run_scale.sh full before/after`
  after a change to any function above; `equiv` after changing what they
  return.
- The migrations patch the live function definitions with text replacements
  (`pg_get_functiondef` + `replace`) and raise if the expected text is gone, so
  a later change to one of those functions by another feature is kept, and a
  conflicting one is noticed at migration time instead of silently undone.
- After `claim_push_delivery` changes, deploy the migrations first and the
  `push` and `scheduled-dispatch` functions after: the new functions pass the
  new arguments.
