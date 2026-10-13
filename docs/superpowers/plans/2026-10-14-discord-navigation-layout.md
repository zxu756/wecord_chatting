# Discord-style navigation

The app used a Material navigation rail (Chats / Contacts / Circles / Me)
with the circle rail nested inside the Circles tab. Discord inverts that: the
server rail is the app's main navigation, and direct messages, friends and the
user's own settings hang off it. This reworks WeCord's navigation the same
way (observed layout only; no Discord code or branding).

## Reference layout (Discord)

- **Desktop:** the server rail runs down the far left: Home (direct messages)
  at the top, a divider, the servers, then "Add a server" and "Discover".
  The second column is the selected place's sidebar. For Home it holds a
  "Find or start a conversation" button, Friends, and the "Direct messages"
  list; for a server it holds the channels. A user panel (avatar, name,
  status, settings) sits at the bottom of that column, with the voice panel
  above it during a call. The main area shows the Friends page, a DM or a
  channel.
- **Phone (current app):** bottom tabs Servers (rail + list), Messages (DMs),
  Notifications (mentions, replies, friend requests) and You (profile and
  settings). The tabs hide inside a conversation.

## WeCord mapping

| Place | Wide (>= 840) | Phone |
| --- | --- | --- |
| Rail | Always on the left: Home, circles, Create/Join, Explore | Inside the Home tab |
| `/home` | Home sidebar + Friends | Home tab: rail + Home sidebar |
| `/circles/:id` | Channel sidebar + channel | Home tab: rail + channel list |
| `/chats` | Same as `/home` | Messages tab (full DM list) |
| `/chats/:id` | Home sidebar + DM | Full screen, no tabs |
| `/contacts` | Home sidebar + Friends | Full screen (from Home) |
| `/notifications` | Home sidebar + Inbox | Notifications tab |
| `/me` | Rail + settings | You tab |
| `/circles` | Redirects to `/home` | Redirects to `/home` |

## Tasks

- [x] Shell: the circle rail replaces the Material rail on wide screens; the
      phone bar becomes Home / Messages / Notifications / You and only shows
      on tab roots. The Home tab returns to the last circle (or Home).
- [x] Rail: Home item with the unread DM badge, Create/Join menu on "+",
      Explore (search) item, voice indicator when the page has no sidebar.
- [x] Home sidebar: search button, Friends (with pending request badge),
      Inbox (wide), Direct messages list (direct and group chats only) with
      the conversation actions on right-click / long press, voice panel and
      user panel.
- [x] User panel at the bottom of the Home and circle sidebars (wide):
      avatar with presence, name, custom status, settings.
- [x] Circle workspace drops its own rail; wide layout starts at 720.
- [x] Inbox: `list_inbox` RPC (mentions of me and replies to my messages,
      visible through RLS) plus pending friend requests; `/notifications`.
- [x] Update tests and phone screenshots.
