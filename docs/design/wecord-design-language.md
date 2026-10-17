# WeCord design language "C"

WeCord's look: warm paper, ink type and one blue accent; big, friendly
type; soft rounded shapes; glass only where something floats. This document
is the spec. The code lives in:

- `lib/shared/theme/wecord_tokens.dart` — tokens (`WeCordTokens` theme
  extension: palette, shadows, glass; `WeCordRadii`, `WeCordSpace`,
  `WeCordSizes`). Read them with `context.tokens`.
- `lib/shared/theme/wecord_theme.dart` — `WeCordTheme.light()/dark()`: the
  Material theme mapped onto the tokens, so stock widgets already fit.
- `lib/shared/ui/` — the core components (`import 'package:wecord/shared/ui/ui.dart';`).

The mockups the owner chose are the reference for every page. They are HTML
files from the design canvas (390×844 phones, 1440×900 desktop):

| Mockup | Shows |
| --- | --- |
| `C-login` | Sign in: hero avatars, large title, labelled filled fields, ink + secondary pills |
| `C-home` | Phone home: rail, panel with rounded corner, quick friends row, conversation rows, floating user panel |
| `C-chat` | Direct chat: glass header, bubble runs, reactions, voice message, glass composer |
| `C-menu` | Long-press menu: blurred chat, quick reactions, action tiles and list in glass |
| `C-circle` | Circle on a phone: banner, event card, channel list, voice channel card |
| `C-voice` | Stage (always dark): speaker tiles, raised hand, audience grid, glass control bar |
| `C-profile` | Profile sheet: banner, big avatar, action row, info blocks |
| `C-settings` | Phone settings: account card, theme picker, grouped rows with icon tiles and switches |
| `C-inbox` | Notifications: chips, cards with action pills |
| `C-dark` | Phone home in the dark theme |
| `C-desk-chat` | Desktop DM: rail + sidebar + chat + profile panel, floating user panel |
| `C-desk-circle` | Desktop circle: channel sidebar, card-style channel messages, member panel |
| `C-desk-settings` | Desktop settings window: nav column, theme cards, segmented controls, switches, slider |

## Principles

1. **Paper and ink.** Pages sit on warm paper; content sits on white
   panels; text is near-black ink. The one accent (blue) marks what's
   interactive or new.
2. **People are circles, things are squircles.** Avatars of people are
   always round (`PersonAvatar`). Circles (servers), groups, apps, bots and
   icon tiles are continuous-corner rounded squares (`ThingAvatar`,
   `SettingsIconTile`).
3. **Glass only floats.** Translucent blur is for things floating over
   content: the floating user panel, chat composer and header, long-press
   menus, toolbars over media. Never for panels, lists or pages.
4. **Big and friendly.** Large titles (26–34, weight 800, tight tracking),
   44+ touch targets, pill buttons, generous rows.
5. **No Material chrome.** No ripples (`NoSplash`), no elevation tints, no
   outlined text fields, no dense list tiles. Feedback is a soft tint plus a
   springy press scale.

## Color

All colors are roles on `WeCordPalette` (`context.tokens.colors`). Don't
use raw hex in widgets.

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| `paper` | `#F5F4F1` | `#111113` | App background behind panels (settings, inbox, sign in) |
| `rail` | `#ECEAE5` | `#111113` | Circle rail |
| `railItem` | `#FFFFFF` | `#1F1F23` | Rail items at rest |
| `sidebar` | `#FAF9F7` | `#18181B` | Desktop sidebars and right panels |
| `panel` | `#FFFFFF` | `#1B1B1E` | Content panels, chat, setting groups, sheets, dialogs |
| `raised` | `#F2F1EE` | `#26262A` | Fills on a panel: icon buttons, inputs, incoming bubbles, icon tiles, chips, selected rows |
| `raisedStrong` | `#ECEAE5` | `#2C2C31` | Fills on paper (secondary pill on sign in) |
| `well` | `#F7F6F3` | `#222226` | Quiet blocks inside a panel (profile sections, quotes, cards) |
| `ink` | `#17171A` | `#F3F2EF` | Text; primary button and outgoing bubble fill |
| `onInk` | `#FFFFFF` | `#111113` | Text on ink |
| `muted` | `#5F5E66` | `#A3A1AA` | Secondary text |
| `subtle` | `#6F6D76` | `#94929A` | Section headers, placeholders (still 4.5:1 on panel and raised) |
| `faint` | `#8D8994` | `#706F78` | Chevrons, disabled, offline (3:1, for icons and dots) |
| `line` | `#E4E2DD` | `#2C2C31` | Borders (fields on paper, theme cards) |
| `lineSoft` | `#EFEDE8` | `#242428` | Separators inside groups and lists |
| `track` | `#D6D3CC` | `#3A3A40` | Off switches, slider tracks, the rail divider |
| `accent` / `onAccent` | `#2F6BF6` / white | `#6E95FF` / `#111113` | Links, compose/send, switches on, unread |
| `accentSoft` | `#E9F0FF` | `#23283A` | Unread row, mentions, selected reaction |
| `accentText` | `#1F5FE0` | `#9DB8FF` | Accent text on panels |
| `success` (+Soft/Text) | `#2E9D67` | `#30A46C` | Online, connected, on |
| `warning` (+Soft/Text) | `#CA8619` | `#E7A53B` | Idle, raised hand, events today |
| `danger` (+Soft/Text) | `#E12F35` | `#E12F35` | Destructive, mention badges, do not disturb (white text on it clears 4.5:1) |
| `scrim` | ink 32% | black 50% | Behind sheets and dialogs |

Presence: online `success`, idle `warning`, do not disturb `danger`,
offline/invisible `faint`.

Avatar fills without a picture come from `WeCordAvatarColors.forSeed(name)`
(eight warm/cool mid tones from the mockups) so a person or circle keeps one
color everywhere.

**Material mapping** (so old code fits until it is restyled): `primary` =
accent, `secondary` = ink, `tertiary` = success, `error` = danger, `surface`
= panel, `onSurfaceVariant` = muted, `outlineVariant` = line,
`surfaceContainerLow` = sidebar (dark: panel), `surfaceContainerHigh` = rail,
`surfaceContainerHighest` = raised, `secondaryContainer` = selected row,
`inverseSurface` = ink. `scaffoldBackgroundColor` is `panel`; pages that sit
on paper (settings, inbox, sign in) set `tokens.colors.paper` themselves.

## Type

Plus Jakarta Sans (bundled variable font, SIL OFL —
`assets/fonts/plus_jakarta_sans/`), with `fontFamilyFallback` to the
platform's color emoji and Chinese font: PingFang SC / Hiragino Sans GB on
Apple platforms, Microsoft YaHei on Windows, Noto Sans SC on Android, Linux
and the web. Every theme text style carries the family and fallback.

| Style | Size / weight / tracking | Use |
| --- | --- | --- |
| `displayLarge` | 34 / 800 / −0.9 | Rare hero numbers |
| `displayMedium` | 32 / 800 / −0.8 | Sign-in headline |
| `displaySmall` | 28 / 800 / −0.6 | Empty-state titles |
| `headlineLarge` | 26 / 800 / −0.6 | **Large page title** (Messages, Settings, Notifications) |
| `headlineMedium` | 24 / 800 / −0.4 | Profile name, desktop settings page title |
| `headlineSmall` | 20 / 800 / −0.4 | App bar titles, dialog and sheet titles, desktop sidebar title |
| `titleLarge` | 20 / 700 | Circle name on banners |
| `titleMedium` | 16 / 700 | Row titles (unread), names in headers |
| `titleSmall` | 14 / 700 | Desktop row titles, tabs |
| `bodyLarge` | 16 / 400 | Message text on phones (15.5 in mockups), inputs |
| `bodyMedium` | 14 / 400 | Previews, descriptions |
| `bodySmall` | 12 / 500, muted | Timestamps, captions |
| `labelLarge` | 14 / 700 | Buttons (buttons use 15–16) |
| `labelMedium` | 12 / 700 | Section headers (with `subtle` color), chips |
| `labelSmall` | 11 / 700 | Badges, tags |

Rows: title 16/600 (700 when unread), preview 14 muted (600 ink when
unread). Section headers: 12/700 `subtle`, sentence case.

## Spacing, sizes and radii

- 4/8 grid: `WeCordSpace.x1…x10` = 4, 8, 12, 16, 20, 24, 32, 40. Phone side
  gutter 16. Rows: 9–12 vertical padding; groups: 14 inside.
- Touch targets ≥ 44 (`WeCordSizes.touchTarget`). Buttons: 54 large
  (full-width phone actions), 44 medium, 32 small. Round icon buttons 40–46
  on phones, 36 on desktop toolbars (hit area still 44 on touch).
- Avatars: 46 rows (phone), 36 rows (desktop), 58 quick-friends row, 30–32
  in bubbles, 40 headers, 80–96 profiles. Squircles radius ≈ size/3
  (46 → 15).

| `WeCordRadii` | Value | Use |
| --- | --- | --- |
| `xs` | 6 | Tags, key hints, bubble tails (`bubbleTail`) |
| `sm` | 10 | Media thumbnails, desktop nav rows |
| `md` | 14 | Icon tiles, desktop rail items, segmented track |
| `lg` | 16 | Inputs, list rows, theme cards, media in bubbles |
| `xl` | 22 | Setting groups, cards, glass menus |
| `xxl` | 28 | Panel top-left corner, sheets, composer, dialogs |
| `pill` | 999 | Buttons, chips, switches, floating bars |
| `bubble` | 20 | Message bubbles (6 where bubbles of a run meet) |

## Elevation, shadows and glass

Elevation is only shadow, never tint (`WeCordShadows`):

- `hairline` — 0 1 3 ink 6%: selected sidebar row, small white buttons on paper.
- `float` — 0 12 32 ink 14%: floating user panel, composer.
- `menu` — 0 18 44 ink 18%: long-press menus, popovers.
- `dialog` — 0 30 80 ink 30%: dialogs, the desktop settings window.

**Glass recipe** (`WeCordGlass`, `WeCordGlassStyle`): fill white 88% (dark:
graphite `#2C2C32` 90%, strong enough that `muted` text keeps 4.5:1 over dark
content), backdrop blur 24 with saturation ×1.8 (dark ×1.6),
1px border white 90% (dark: white 8%), shadow `float` or `menu`.
Solid fallback: `glass.solidFill` with a `line` border. Glass turns solid
when **Settings → Appearance → Glass effects** is off, or when the platform
asks for reduced motion or high contrast (`WeCordAppearance.glassOf`).

## Motion and haptics

Spring based (`lib/shared/ui/motion.dart`); each `WeCordSpring` gives a
`curve` and the `duration` it needs to settle:

| Spring | Stiffness / damping ratio | Use |
| --- | --- | --- |
| `WeCordMotion.snappy` | 520 / 0.86 (≈ 0.3 s) | Press scale, switches, segmented thumb |
| `WeCordMotion.smooth` | 300 / 1.0 (≈ 0.5 s) | Sheets, panels, floating bars |
| `WeCordMotion.bouncy` | 420 / 0.68 | Badges popping in, reactions, menus opening |

Color/hover changes use `WeCordMotion.quick` (120 ms) with
`WeCordMotion.standard` (easeOutCubic). Presses scale to 0.97 (icon buttons
0.92). With reduced motion (`MediaQuery.disableAnimations`) use
`spring.durationOf(context)` / `WeCordMotion.durationOf` — they return zero.

Haptics (`WeCordHaptics`): `selection` for switches, segments, chips and
sheet detents; `light` for long-press menus and sending; `medium` for push
to talk and joining calls; `heavy` only to confirm something destructive.

## Components (`lib/shared/ui`)

| Component | Use it for |
| --- | --- |
| `WeCordPressable` | The interaction core instead of InkWell: hover + pointer cursor, focus ring, Enter/Space, press scale, semantics. Build custom rows/tiles on it. |
| `WeCordButton` | Pill buttons. Variants: `primary` (ink), `accent`, `secondary` (raised), `ghost`, `danger`, `onPaper` (white on paper). Sizes `large` 54 / `medium` 44 / `small` 32; `expand`, `loading`, `icon`. |
| `WeCordIconButton` | Round icon button with required tooltip (its a11y label), optional `badgeCount`, `selected`. |
| `WeCordTextField` | Filled borderless field with the label above it (`onPaper` for white-on-paper with a hairline), `labelTrailing` for "Forgot password?". Focus = accent edge. |
| `WeCordSegmented<T>` | iOS-style segmented control with a sliding white thumb. |
| `WeCordSwitch` | iOS-style switch (46×28; `compact` 42×26 on desktop). |
| `SettingsGroup` / `SettingsRow` / `SettingsRow.toggle` / `SettingsIconTile` / `SettingsSectionHeader` | Grouped rounded setting cards: icon tile (tones neutral/accent/success/warning/danger), title, subtitle, value + chevron, trailing widget or switch. |
| `CountBadge` / `CountBadge.dot` | Count pills (`alert` red, `unread` accent, `quiet`), 99+, optional cut-out ring. |
| `WeCordChip` | Filter/tab chips: ink when selected; `onPaper` for white chips on paper; `count`. |
| `PersonAvatar` | Circle avatar with initial/photo and presence dot (or any `badge`). |
| `ThingAvatar` (alias `SquircleAvatar`) | Squircle for circles, groups, apps, with icon or initial and a corner `badge`. |
| `PresenceDot` | The dot alone, ring cut from its background. |
| `PanelSurface` | The white panel with the big top-left radius beside the rail. |
| `WeCordGlass` | Floating glass surface (`GlassElevation.flat/float/menu`). |
| `FloatingUserPanel` | Layout of the glass user pill (avatar, name, status, actions); data stays with the caller. |
| `showWeCordSheet` / `WeCordSheet` | Bottom sheets: 28 corners, grabber, optional title; `detents` (e.g. `[0.5, 0.92]`) make it a snapping draggable sheet. |
| `WeCordMotion` / `WeCordSpring` / `SpringCurve` / `WeCordHaptics` | Motion and haptics above. |
| `MacosTitleBarFrame` / `MacosWindowDragArea` / `macosTitleBarInset` | The macOS window under a transparent title bar (below). |
| `MediaTray` / `MessageMediaGroup` / `MediaTile` (`lib/features/chats/media_send/`) | Sending pictures, videos and files: the glass tray above the composer (72–84 thumbnails, remove badges, caption, "Original quality" switch, accent send pill), and the album grid in a bubble (justified rows, 2 px gaps, 16 outer / 4 inner corners, BlurHash under every tile, progress ring with a cancel button while uploading, a red retry button once failed). `ChatDropOverlay` is the dashed accent frame and glass card shown while files are dragged over the chat. |
| `WeCordTapTarget` / `touchTargetFor` | Grows a control's tappable and accessibility area to the platform's touch target (48 Android, 44 iOS, none on desktop) without changing how it looks; `WeCordPressable` applies it by default (`minTapSize`). |
| `MotionSafeImage` | Pictures that can animate: still under reduced motion with a play button. |
| `MessageFrame` (`lib/features/chats/message_semantics.dart`) | A chat message as one stop for screen readers ("{sender}, {time}: {text}, {n} reactions", actions as custom actions) and the keyboard (focus ring, context menu key / Shift+F10 / Enter open its menu). |
| `WhenSheet` / `showWhenSheet` (`lib/features/later/`) | The "when" picker of Schedule message and Remind me: a grouped list of quick picks with their times and "Pick date and time" (date and time pickers in the device's time zone, which the row names). Times are built from wall-clock fields (`later_time.dart`), so "tomorrow at 9 am" survives daylight saving changes. |
| `LaterCard` / `ReminderCard` / `LaterMessagePreview` (`lib/features/later/later_cards.dart`) | White cards on paper for reminders (Notifications) and saved messages: sender avatar with a small round badge, the message in a `well` box or an italic "Message unavailable", small pill actions. |
| `ResizableDivider` | The handle on a resizable column's edge (below): 8 px hit strip, resize cursor, accent line on hover/drag/focus, spring settle, double-click reset, keyboard and slider semantics. `ResizableSidebarRow` / `ResizableSidePanelRow` (`lib/shared/layout/resizable_panels.dart`) wire it to the saved widths. |
| `NoteEditor` / `NotePage` / `TaskListPage` / `TaskBoardView` / `WorkspacePanel` (`lib/features/notes`, `lists`, `workspace`) | Shared notes and task lists of a conversation: the block editor with its format bar and carets of other people, the list and board views, and the panel/page that holds them (see Notes and Lists below). |

Material widgets still work and are themed: `FilledButton` = ink pill,
`OutlinedButton` = secondary raised pill (no outline), `TextButton` =
accent text, inputs are filled (`WeCordFieldBorder` keeps floating labels
inside the fill), `Card` = `well`, `ListTile` 16-radius, dialogs and sheets
28-radius on `panel`, floating ink `SnackBar`, ink tooltips, iOS-colored
`Switch`, segmented buttons on a raised track, round thin scrollbars. Prefer
the WeCord components in new and restyled screens.

## Layout

### Phone (< 840 wide)

- **Home / circle**: rail 68 wide on `rail`, items 46 squircles 10 apart from
  y≈58; the panel (`PanelSurface`, top-left radius 28) starts 46 below the
  top. Large title row: 26/800 title + 40px round buttons (search raised,
  compose accent).
- **Floating user panel**: glass pill, 64 tall, radius 32, 28 above the
  bottom, spanning from 10 px inside the rail's left to 10 px from the right
  edge; lists end above it.
- **Pushed pages** (chat, settings, inbox): full screen. Chat: white page,
  glass header with bottom radius 24, glass composer pill (radius 28) 28
  above the bottom with a raised + button, field, emoji/GIF and accent
  mic/send. Settings/inbox: `paper` page, white round back button
  (`WeCordIconButton` variant `onPaper`), 26/800 title, `SettingsGroup`s.
- **Sheets** for profiles and pickers: `showWeCordSheet`, top at ~92 for
  profile-size sheets (`detents: [0.5, 0.9]`).
- Bubbles: incoming `raised`, outgoing `ink` with `onInk` text, radius 20
  with 6 where a run continues, max 72% width.

### Desktop / web / macOS (≥ 840)

- Rail 72 (`WeCordSizes.railDesktop`), items 44 squircles radius 14, a 4×30
  ink pill at the left edge marks the selection.
- Sidebar on `sidebar`, top-left radius 22, starting 10 below the
  window top; selected row = white with `hairline` shadow. Home's direct
  messages and a circle's channels share one width: 292, resizable
  220–420.
- Content on `panel` with a 1px `lineSoft` left edge; header 58 with a
  hairline bottom border, 36 icon buttons, a raised search field (200 wide).
- Optional right panel on `sidebar`: the circle member list (248,
  resizable 200–360) or a direct chat's profile (300, resizable 240–420).
  The header toggle opens and closes it.
- **Resizing**: drag a column's edge (`ResizableDivider`); ←/→ move it by
  16, Home/End go to the limits, double-click or Enter resets. Past the
  range the edge resists and springs back; a right panel dragged 60 below
  its minimum snaps shut. Widths and closed panels are kept per device
  (`panelLayoutProvider`). The centre content keeps at least 420
  (`WeCordSizes.contentMin`): when the window is too narrow, right panels
  close first (and come back when there is room, unless the user closed
  them), then the sidebar shrinks toward 220. The rail stays 72.
- Floating user panel: glass, 58 tall, radius 29, 14 above the bottom,
  spanning rail + sidebar (left −62 relative to the sidebar, right 10) and
  following the sidebar's width.
- Settings opens as a centered window (radius 28, `dialog` shadow) over the
  blurred app: nav column 248 + content with 24/800 title.

## Platform notes

- **macOS**: the window draws under a transparent, hidden title bar
  (`MainFlutterWindow.swift`: `titlebarAppearsTransparent`, `.hidden` title,
  `.fullSizeContentView`, minimum 960×640). `MacosTitleBarFrame` (in the app
  builder) reports 28 px top padding so app bars and safe areas clear the
  traffic lights, and lays a `MacosWindowDragArea` over the top strip that
  starts a native window drag (channel `wecord/window`, method
  `startDrag`). The desktop shell removes that padding again; its rail
  keeps 28 px clear itself (`macosTitleBarInset`). Keep interactive
  controls out of the rail's top 40 px.
- **Web and desktop**: everything clickable shows the pointer cursor and a
  hover tint, and draws a 2px accent focus ring when reached by keyboard
  (`WeCordPressable`); Enter/Space activate. Tooltips on icon-only buttons.
  `⌘K`/`Ctrl K` hint in the sidebar search.
- **Reduced motion**: springs collapse to zero duration; glass goes solid;
  animated pictures (GIFs) hold their first frame under a play button
  (`MotionSafeImage`) in message pictures, album tiles, the full-screen
  viewer and avatars (avatars under 72 px just stay still: the button would
  cover them); videos do not start by themselves.
- **High contrast**: the platform's "Increase contrast" selects
  `WeCordTheme.light/dark(highContrast: true)` (`MaterialApp.highContrastTheme`):
  `WeCordPalette.lightHighContrast` / `darkHighContrast` (ink black/white,
  `muted` ≥ 7:1, lines, switch tracks and the glass edge ≥ 3:1) and solid glass.
- **Glass effects off switch**: Settings → Appearance (persisted like the
  theme mode, `glassEffectsProvider`).
- **Density**: Settings → Appearance → Density (Comfortable / Default /
  Compact, kept per device, `densityProvider`). `context.density`
  (`WeCordDensityScale`) scales list rows (direct messages, channels,
  members), message gaps and card avatars. On touch screens Compact only
  tightens a little and rows stay at least 44.
- **Chinese**: the CJK fallback renders Chinese in the platform font;
  Chinese titles keep the same sizes and weights (letter-spacing is
  harmless).

## Do / don't

- Do use `context.tokens.colors.*`; don't use `Colors.*` or hex except
  white text on avatar fills.
- Do use `PersonAvatar` for people and `ThingAvatar` for everything else;
  don't put a person in a squircle or a circle (server) in a circle.
- Do use glass only on floating elements; don't blur whole panels.
- Don't add InkWell ripples, elevation tints or outlined text fields.
- Don't brand anything after another product; all artwork is original.

## Accessibility

- **Contrast** (WCAG AA): text 4.5:1, icons and dots 3:1, checked for every
  token pair in `test/accessibility/token_contrast_test.dart` (light, dark and
  both high contrast sets). Glass keeps `ink` and `muted` readable over
  worst-case content. Avatar fills are deep enough for their white initial.
- **Guard**: `test/accessibility/guidelines_test.dart` runs Flutter's
  `androidTapTargetGuideline`, `iOSTapTargetGuideline`,
  `labeledTapTargetGuideline` and `textContrastGuideline` over the main screens
  (`test/accessibility/a11y_screens.dart`) in light, dark and with high
  contrast; add a screen there when you add one. `semantics_test.dart` covers
  message reading, keyboard and reduced motion.
- **Touch targets**: ≥ 48 on Android, ≥ 44 on iOS, through `WeCordPressable`;
  a visible 32–40 control is padded invisibly. Rows and bars that hold fixed
  heights must use `minHeight` so large text grows them.
- **Screen readers**: icon-only buttons get their tooltip as label; rows
  read as one sentence (`conversationRowLabel`, `messageSpokenSummary`);
  badges read counts (`CountBadge`: "3 unread"), presence dots read their
  status; decorative icons and pictures are skipped; the typing indicator,
  composer errors and incoming messages in the open chat are live regions /
  announcements; menus are named routes. New strings go through `tr()` with
  Chinese in `lib/shared/l10n/zh/zh_a11y.dart`.
- **Keyboard** (desktop and web): every pressable has the focus ring; Tab
  reaches messages; the context menu key or Shift+F10 opens the focused
  message's menu, Esc closes it and focus returns; Ctrl/Cmd+J jumps to the
  message box.
- **Text size**: layouts are checked at 1.6× and 2.0× with
  `tool/screenshots/a11y_screenshots_test.dart` (also dark and high
  contrast, into `build/a11y/`). Large page titles shrink to fit their row;
  buttons, chips and cards grow. Desktop sidebars are checked at 2.0x too
  (the `desktop-*-2x-text` screens, and `test/accessibility/large_text_test.dart`
  fails when text in a sidebar row is taller than the row): rows use
  `minHeight`, never a fixed `height`.

## Notes and Lists

Every conversation (circle channel, group or direct chat) can have shared
**notes** and **task lists**. They live in `lib/features/notes/`,
`lib/features/lists/` and `lib/features/workspace/`; the backend is
migrations `202610170060` to `065`.

**Where they show up.** The chat header has *Notes* and *Lists* buttons (in
More on phones). On desktop they open a right-hand panel
(`ResizablePanel.docs`, 440 wide, 340–760, resizable like the others; it takes
the profile panel's place and closes first when the window is narrow). On
phones, and from links, they open as full pages at
`/chats/:id/workspace?tab=&note=&list=&item=`. A note can be **pinned**: it
shows as a slim accent banner under the chat header. Notes also appear in the
quick switcher (by title), shared notes, tasks and lists are **cards** in the
chat, and the message menu has **Create task** (the task links back to the
message and the message shows its task with a check box).

**Notes are block documents.** A note is a list of blocks (paragraph, h1–h3,
bullet, numbered, to-do, quote, code, divider, picture), each its own row in
`note_blocks` with a fractional ordering key (`lib/shared/models/fractional_key.dart`),
a revision, inline marks (bold, italic, strike, code, link, mention) and
properties. Why not a CRDT: there is no maintained Dart Yjs-compatible
package, and blocks give per-block last-writer-wins with real merging where it
matters:

- `note_apply_ops` applies a change only if it was based on the block's
  current revision; otherwise it answers with the current block. The client
  (`NoteSyncEngine`) merges three ways — text by the one contiguous edit each
  side made (both kept when apart, both texts kept when they overlap), marks
  character by character (what either side removed is gone, what either side
  added stays), kind/position/props field by field — and sends again.
  Nothing typed is dropped and nothing is overwritten blindly.
- Offline edits stay dirty and are kept on the device (`NoteDraftStore`); when
  the connection returns, or the note is reopened, the server's state is merged
  into them exactly like a live change. Creating a block is idempotent (same
  id, same content), deletes win and are tombstoned.
- Realtime streams `note_blocks`; presence/cursors ride a Realtime presence
  channel (`note-presence-<id>`: name, block, offset), drawn as a coloured
  caret with the person's name.
- History: a snapshot is taken before the first change after 10 quiet
  minutes (and every 30 minutes of continuous work), or on demand; restoring
  snapshots what it replaces first.

**Who can do what** (enforced in SQL, `can_current_user_*_note`): anyone who
can see the conversation reads; anyone who can send there edits; *Only
managers can edit* (per note) limits editing to `manage_messages` holders (or
group admins); pinning, locking and deleting others' notes are manager actions.
Lists follow the same rule (view = see the conversation, edit = send; the
author or a manager deletes a list). Pictures live in the private
`note-files` bucket with policies like `chat-files`.

**Editor.** Design C throughout: 28/800 titles, paper-white panel, ink text,
accent only for links, mentions and the caret. Shortcuts: ⌘/Ctrl+B, I, E
(code), Shift+X (strike), K (link); markdown at the start of a paragraph:
`# `, `## `, `### `, `- `, `* `, `1. `, `[] `, `[x] `, `> `, ` ``` `; `---`
then Enter makes a divider; `/` opens the block menu; Enter continues lists
and ends them on an empty item; Backspace at the start turns a block back into
text, then joins it to the one before. The format bar floats as glass over the
keyboard on phones and is a flat bar on desktop.

**Lists.** Items have a title, notes, status (To do / In progress / Done or
the list's own, each of kind *todo*, *active* or *done*), priority, due date
(all-day or with a time), up to 10 assignees and the message they came from.
Item changes are field patches (`upsert_task_item`), so two people changing
different fields never undo each other. The list view groups by status with
filters (All, Mine, Overdue, Open) and sorting; the board has a column per
status and drag and drop (long press on touch; auto-scroll at the edges; every
move is also an accessibility action "Move to …").

**Notifications.** Assigning someone makes an inbox entry (`task_notifications`,
the *Tasks* chip on the Notifications page) and a push: the assigner's app calls
the `push` Edge Function with `{task_item_id}`, which claims the assignment
pushes (`claim_task_assignment_push`) once. **Due reminders** are for the
scheduler (the pg_cron dispatcher): call

```sql
select * from public.due_list_item_reminders();
```

every few minutes with the service role. It creates the `due_soon` (within an
hour; all-day items within 12 hours) and `overdue` notifications that are new
(one per person, item and due date) and returns one row per push subscription
to notify: `notification_id, user_id, subscription_id, endpoint, p256dh,
auth, conversation_id, circle_id, title, body`. Deliver each row as a web push
like the `push` function does (`title`/`body`, target
`/#/circles/<circle_id>?c=<conversation_id>` or `/#/chats/<conversation_id>`),
and drop subscriptions the push service reports gone with
`remove_push_subscriptions`. People in do-not-disturb or with the circle level
"none"/muted get the inbox entry but no push.

**Accessibility.** Rows read as sentences; check boxes say "Mark "x" as done";
the editor's blocks are text fields with hints, the other people's carets have
labels ("Bart is here"), the save state ("Saved / Saving… / Offline") is a live
region, board cards offer "Move to …" actions, and everything is covered by
`test/accessibility` (screens `notes-index`, `note-editor`, `lists-index`,
`task-list`, `task-board`, `task-sheet`).
