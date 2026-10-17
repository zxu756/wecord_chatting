# Calls: links, mini player, reactions, screen zoom, background blur

How the call extras work and what each platform supports. The code lives in
`lib/features/voice/` (`call_links/`, `mini_player/`, `reactions/`,
`screen_zoom/`, `background/`).

| | Web | macOS | iOS |
| --- | --- | --- | --- |
| Call links (create, copy, revoke) | yes | yes | yes |
| Opening a call link in the app | by the address (`/call/<code>`) | in-app route; links open in the browser | in-app route; links open in the browser |
| Mini player (in-app picture in picture) | yes | yes | yes |
| System picture in picture | no | no | no (see below) |
| Reactions | yes | yes | yes |
| Screen share zoom, pan and spotlight | yes (pinch, wheel, drag, keys) | yes | yes (pinch, drag; no screen sharing from iOS) |
| Background blur | yes, WeCord's own (tried in Chrome; Safari and Firefox take the library's canvas path and were not tried) | the system's Portrait effect, opened from the app | the system's Portrait effect, opened from the app (iOS 16+) |

## Call links

`https://wecord.jokebear.fyi/call/<code>` (12 characters). "Copy call link"
sits in a call's header (voice channels) or call card (direct and group
chats) and opens a sheet: choose 24 hours, 7 days or no expiry, copy a new
link, copy or revoke the ones made before.

- Backend: `supabase/migrations/202610170040_call_links.sql`. The
  `call_links` table takes no direct writes; `create_call_link`,
  `list_call_links`, `revoke_call_link` and `resolve_call_link` do the work.
  Only the creator lists or revokes a link, and at most 50 can be active.
- A link grants nothing. Opening it asks `resolve_call_link`, which checks
  what joining checks (`can_current_user_call_in_conversation` for a chat,
  `can_current_user_connect_voice` for a voice channel). Without access the
  answer is just `no_access`: the page says so and reveals nothing about the
  call.
- Routing: `/call/:code` in go_router. Signed-out visitors go through sign-in
  and continue (`?from=`, like invite links). On the web the address has no
  `#` route, so `callLinkLocationFor(Uri.base)` turns
  `https://site/call/<code>` into the initial route.
- Native apps: the link opens in the browser (the web app). Opening it in
  the iOS and macOS apps needs Universal Links, which need the Associated
  Domains entitlement and an `apple-app-site-association` file on the site;
  that is not set up. The in-app route works as `/call/<code>`.

## Mini player (in-app picture in picture)

While connected to a call and no page shows it (the voice room, a chat's call
card, the stage), a draggable window floats over the app with the active
speaker's video or avatar, mute and leave. Tapping it returns to the call; it
snaps to the nearest corner when let go; screen readers get "Move to ..."
actions. `CallSurface` marks the places that show the call; pages covered by
another page don't count.

System picture in picture is **not** available: neither `livekit_client` nor
`flutter_webrtc` offers it (the only trace is LiveKit's README asking for the
"Audio, AirPlay, and Picture in Picture" background mode), and doing it on
iOS would mean native `AVPictureInPictureController` code with a sample
buffer renderer for WebRTC frames. So it is in-app on every platform.
(Background audio continues as before.)

## Reactions

The reactions button in the control bar sends one of 👍 ❤️ 😂 😮 👏 🎉 as a
LiveKit data message (topic `wecord.reaction`, `{"v":1,"e":"👍"}`). It floats
up over the sender's tile for everyone. Limits: five per three seconds when
sending, eight per three seconds per sender when receiving, eight on one tile
at a time; anything not in the list is dropped, and the sender is the
identity LiveKit reports, not the message. With reduced motion the emoji
appears and fades in place. Stage channels don't have the button (the
audience can't publish data).

## Screen share zoom and pan, and focus

Pinch, scroll wheel (or trackpad pinch) zoom a shared screen up to 8x; drag to
pan; double-tap or double-click resets (or zooms to 2.5x when not zoomed).
Keyboard: + / - / 0 / arrows when the tile has focus. A pill shows the zoom
with buttons. While zoomed the call page doesn't scroll, so a finger drags the
picture. "Focus this tile" (or tapping a person's tile) spotlights it large
with everyone else in a strip below; tap again to show everyone.

## Background blur

| Platform | What happens | How |
| --- | --- | --- |
| Web (browsers with OffscreenCanvas, VideoFrame, createImageBitmap and WebGL 2) | WeCord blurs the camera before it is sent. A blur button appears next to the camera button while the camera is on; the choice is remembered. | LiveKit `@livekit/track-processors` 0.8.2 (MediaPipe selfie segmentation) loaded from jsDelivr on first use (an import map in `web/index.html`, `web/blur/livekit_client_shim.js`). Through `LocalVideoTrack.createCameraTrack(processor)`. Verified in headless Chrome with a fake camera: the processed track is what LiveKit sends, and blur switches on and off without a restart. |
| macOS 12+, iOS 15+ (iOS 16+ to open the panel) | The system's Portrait effect, which blurs the background for any app using the camera. Apps cannot switch it on; the "Video effects" button opens the system panel (Control Center) and the button shows whether it is on. Hidden when no camera supports Portrait. | `AVCaptureDevice.isPortraitEffectEnabled`, `showSystemUserInterface(.videoEffects)` in `VideoEffectsPlugin.swift` (channel `wecord/video_effects`). |
| Elsewhere | The option is not shown. | |

Notes:

- A camera that should be blurred is never sent unblurred. Where WeCord blurs
  the picture itself, the camera is stopped and started again (not just
  muted) whenever it goes off and on, because livekit_client puts the
  unprocessed picture back on a muted camera that is unmuted. If the blur
  can't start (no network for the library, an unsupported browser after
  all), the camera stays off, the user is told, and blur is switched off so
  the next try starts the camera plainly.
- Virtual (image) backgrounds are supported by the same library but are not
  offered: they need background pictures to choose from.
- Native in-app blur (Vision person segmentation and Core Image in a
  flutter_webrtc `ExternalVideoProcessingDelegate`) would also be possible
  on iOS and macOS, but the system's effect does the same with less power and
  no frame copies, and could not be checked against a live camera here.
