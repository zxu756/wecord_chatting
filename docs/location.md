# Location: sending a place and sharing it live

Code: `lib/features/location/`. Database: `supabase/migrations/202610180050_location.sql`.

## What it does

- **Send a location** (chat + menu, *Location*): a map opens on where the person is (after the system
  permission prompt). They drag the map under a fixed pin, or pick from the places nearby, or search.
  *Send* posts a card: a small map, the place name and the address. Tapping a card opens the full map
  with a pin, *Open in Maps* (Apple Maps on iOS and macOS; Google Maps or OpenStreetMap on the web)
  and *Copy address*.
- **Share live location** (direct chats and groups, *Share live location*): a consent sheet every time
  (15 minutes, 1 hour or 8 hours; *Precise location* off by default, which shares a spot snapped to a
  grid of about 500 m). A banner under the chat header says "N people sharing location" and opens one
  map with everyone's avatar, moving. Sharing ends when time runs out, on **Stop**, when the person
  leaves the chat, and at sign out.

A location is a `text` message with `attachment {kind: 'location', lat, lng, name, address}` (like
note and task cards); its body is a readable line ("📍 Big Ben · Westminster"), so previews, pushes,
search and older apps still make sense. A live location card is `{kind: 'live_location', share_id,
ends_at, precise}`; whether it still runs comes from the share.

## Maps provider (set at build time)

`flutter_map` with OpenStreetMap-compatible tiles. Everything is a `--dart-define` (also usable from
`.env` with `--dart-define-from-file`):

| Define | Default | Meaning |
| --- | --- | --- |
| `MAP_TILE_URL` | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | Tile URL template |
| `MAP_ATTRIBUTION` | `© OpenStreetMap contributors` | Credit shown on every map (keep it right for your provider) |
| `MAP_ATTRIBUTION_URL` | `https://www.openstreetmap.org/copyright` | Where the credit links |
| `GEOCODER_URL` | `https://nominatim.openstreetmap.org` | Nominatim server (search, naming a spot) |
| `PLACES_URL` | `https://overpass-api.de/api/interpreter` | Overpass endpoint (places near a point) |
| `MAP_USER_AGENT` | `WeCord/1.0 (https://wecord.jokebear.fyi)` | Identifies the app on native builds |

**Production should not use the public OSM servers.** They are for light use under the
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/) and the Nominatim and
Overpass policies. The defaults keep to them (identifying `User-Agent` on native builds, the browser's
`Referer` on the web, visible attribution, tile caching on disk on native, one Nominatim request per
1.1 s, one Overpass request per 2 s, cached results, no search-as-you-type below two letters), but
real traffic needs a provider with a key. Example for MapTiler:

```
--dart-define=MAP_TILE_URL=https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=KEY
--dart-define=MAP_ATTRIBUTION="© MapTiler © OpenStreetMap contributors"
--dart-define=MAP_ATTRIBUTION_URL=https://www.maptiler.com/copyright/
```

(Stadia, Mapbox raster, or your own tile server work the same way. Search and nearby places can move to
the provider's geocoder or your own Nominatim/Overpass the same way.)

### Why Nominatim and Overpass instead of native MapKit search

Search, naming the pin and "nearby places" use Nominatim and Overpass (both OpenStreetMap data, both
configurable, both behind the `PlacesService` interface). MapKit search through a small plugin would
give richer results on iOS and macOS, but it does not exist on the web, so a second code path would be
needed anyway, and it cannot be exercised without a device. One path means one set of tests with fake
services. The `PlacesService` interface is where a MapKit plugin would plug in later.

## Privacy and how positions travel

- **Consent** is asked every time sharing starts (nothing is remembered, there is no "always").
- **Positions are not stored.** `live_location_shares` holds who shares in which chat, until when and
  whether precise: no coordinates (checked by `test/supabase/location_test.dart`). Positions are Realtime
  *broadcast* messages on one private channel per share, `live-location:<share id>`.
- **Only members, with blocks respected.** Policies on `realtime.messages` decide who may join the
  channel: only members of that chat, not people blocked either way with the sharer, only while the
  share runs, and not while the card is waiting for review (AI guard) or has been deleted. Only the
  sharer may send. Blocks are therefore enforced per share by the server, not by hiding in the client.
- **Coarse by default.** Without *Precise*, the device snaps the position to a ~500 m grid before it
  sends, and sends no accuracy or heading. (This is done on the device: the server never sees a
  position and so cannot coarsen it.)
- The map checks the list of shares with the server every 45 s, so a block, a deleted card or a share
  ended elsewhere shows up.
- Realtime checks channel policies when a channel is joined and when the token refreshes, not on every
  message. After a new block, a listener could keep receiving until they re-join, and the app drops the
  channel at the next 45 s check. For hard enforcement, in the Supabase dashboard (Realtime settings)
  turn off *Allow public access* so only private channels can be joined; today other features (typing,
  note presence, voice states) use public channels, so that is a separate migration. The channel names
  are unguessable UUIDs that only members can read from `live_location_shares`.

## Background

The app has **no background location mode** (no `UIBackgroundModes: location`, no always permission).
On iOS sending pauses when WeCord is not in front (and in a background browser tab) and resumes when it
is back. The UI says so ("Sharing pauses when WeCord is closed.") and the map marks someone whose
position is older than 45 s as *Paused · last seen …*. A share still running when the app restarts
within its time is picked up again if location is still allowed (otherwise it is ended).

## Platform setup

- iOS: `NSLocationWhenInUseUsageDescription` in `ios/Runner/Info.plist`.
- macOS: `NSLocationUsageDescription` (and When-In-Use) in `macos/Runner/Info.plist`, and
  `com.apple.security.personal-information.location` in both `DebugProfile.entitlements` and
  `Release.entitlements`.
- Web: the browser's geolocation needs https, which the site has.

## Tests

`test/features/location/` (models, places parsing and rate limits, sharer, providers, screens, chat
integration; all on fake services and fake map tiles, never the network),
`test/supabase/location_test.dart` (+ `location_behaviour.sql`, rolled back), the screens in
`test/accessibility/location_a11y_screens.dart`, screenshots with
`flutter test tool/screenshots/location_screenshots_test.dart --dart-define=LOCATION_SCREENS_DIR=build/location`.

Needs a real device: the system permission prompts, real GPS readings and accuracy, the pause when
backgrounded on iOS, Apple Maps opening, and Realtime private channels against the hosted project (the
policies are tested in the database, the broadcast itself is not).
