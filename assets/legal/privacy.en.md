> **Draft — pending owner review.** This text is a working draft. It is not final and may change before it takes effect. It describes how WeCord works today; the owner must confirm the operator's details, hosting regions and contact address.

# Privacy Policy

This policy explains what information WeCord handles, why, who else receives it, and what you can do about it. It is part of the [Terms of Service](wecord:terms). Please also read the [Community Guidelines](wecord:guidelines).

## 1. What we collect

**Information you give us**

- Account: email address, password (stored as a hash by our authentication provider), username, display name, and, if you add them, avatar, banner, bio, pronouns and status.
- Content: messages, photos, videos, voice messages, files, polls, locations, notes, task lists, Moments, circle posts, reactions, events and settings. Content in direct chats and groups is visible to the people in the chat; content in circles is visible to the circle's members, according to the circle's permissions.
- Reports you file, and what you write in them.

**Information from your use of WeCord**

- Devices and sessions: device name, platform, app version, approximate last-active time and sign-in alerts, so you can see and sign out your devices.
- Presence and typing signals, if you leave them on (Settings → Privacy & Safety lets you choose who sees your online status and read receipts).
- Notification settings, and, if you turn on push notifications, a push subscription from your browser or device.
- Crash and error reports (see section 3).
- Standard technical data our providers receive when your device connects, such as your IP address.

We do not sell your information, and we do not show advertising.

## 2. Why we use it

To run WeCord: deliver messages, show profiles, make calls, send notifications, keep the service safe (spam checks, abuse reports, security alerts), fix problems, and follow the law.

## 3. Who else receives it

WeCord uses these services. Each receives only what it needs for its part.

- **Supabase**
  - Database, sign-in, file storage, realtime updates and our server functions.
  - **Receives:** All your account data and content, stored on Supabase's infrastructure. *[Hosting region to be confirmed.]*
- **LiveKit Cloud**
  - Voice and video calls, stages and screen sharing.
  - **Receives:** Your audio, video and screen streams while you are in a call, and your user name and ID in the room. Noise suppression runs on your device.
- **OpenCode Go (AI provider)**
  - AI features: translation, summaries, rewriting, answers from the AI assistant and, in circles that turn it on, the AI guard that checks new members' messages. Voice transcription on the web uses a speech service if one is set up.
  - **Receives:** **Only when you use an AI feature** (or, for the AI guard, when a new member posts in a circle that turned it on): the text involved, and the audio for web transcription. On iPhone and Mac, voice messages are transcribed on your device.
- **Gotenberg (on Google Cloud Run)**
  - Previews of Word, PowerPoint and Excel files on the web.
  - **Receives:** The file you open, so it can be converted to PDF; the result is cached in private storage. On iPhone and Mac, previews are made on your device.
- **OpenStreetMap, Nominatim and Overpass**
  - Map tiles, address search and nearby places when you send or view a location.
  - **Receives:** The map area you view, what you search for, and your IP address. Your position is shared with chat participants only when you send it or start sharing it live.
- **GIPHY**
  - GIF search.
  - **Receives:** Your search words (through our server).
- **Web push services** (Apple, Google, Mozilla, depending on your browser)
  - Delivering push notifications.
  - **Receives:** A push address for your browser or device, and the notification text (message previews are short and follow your notification settings).
- **Link previews**
  - Our server fetches a page to show a title and picture when a message contains a link.
  - **Receives:** The link, from our server.

**Crash and error reports.** The app records crashes, unhandled errors and failed requests and sends them to our own server so we can fix them. They never include message content, file names, your email address or your tokens. You can turn this off in Settings → Privacy & Safety. They are deleted after 30 days.

We may also share information when the law requires it, to protect people's safety, or if WeCord is transferred to another operator.

## 4. Reports and moderation

When you report a message, we keep a copy of it (text, attachment details, sender and time), and, if you agree to "Include context", up to five messages before and after it that you could see. View-once photos and videos are never copied. Only the people who handle the report can read it: the moderators of the circle for reports from a circle, and the WeCord team for reports from direct chats and groups. The person you report is not told who reported them. The copy is erased 90 days after the report has been handled.

## 5. How long we keep it

- Your account data and content stay until you delete them or your account.
- Disappearing messages are removed when their timer ends. Deleted (recalled) messages and their files are removed.
- Crash reports: 30 days. Data export files: removed automatically after they expire.
- Report copies: 90 days after handling.
- Backups and logs at our providers may keep data for a short time longer.

## 6. Your choices and rights

- **Export your data.** Settings → Privacy & Safety → Export my data gives you a ZIP of what you wrote and uploaded. Content that belongs to others is not included.
- **Delete your account.** Settings → Account → Delete account. If you own a circle with other members, transfer it first. Your profile is wiped and your sign-in is removed; your photos, banner and Moments files are deleted. Messages you sent in other people's chats stay, under the name "Deleted User", so conversations keep making sense for the others.
- **Control who sees what.** Profile visibility, online status, read receipts, who can see your Moments, blocking, and which notifications you get.
- **Turn features off.** Crash reports, AI features, push notifications and location sharing can be turned off.
- Depending on where you live, you may also have rights to access, correct, restrict or object to our handling of your information, and to complain to a data protection authority. Contact us (below) and we will help.

## 7. Children

WeCord is for people who are at least {minimumAge} years old. We do not knowingly collect information from younger children. If you think a child below that age has an account, tell us and we will delete it.

## 8. Security

Data is encrypted in transit. Access to your data is controlled by row-level rules in the database, and administrators can read reports but not your chats. No service is perfectly secure. Please use a strong password and two-step verification (Settings → Privacy & Safety).

## 9. International transfers

Our providers may process data in other countries than yours. *[The owner must confirm the regions and, where required, the legal basis for transfers.]*

## 10. Changes

We will update this policy when WeCord's data flows change, and tell you in the app when the change matters.

## 11. Contact

*[Operator name and contact address for privacy questions: to be added by the owner.]*
