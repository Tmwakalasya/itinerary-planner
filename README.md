# City Tourist

A day-by-day itinerary planner for city breaks, built in SwiftUI against the
brief in *Project Brief – City Tourist App*. The visual language follows
Airbnb's: Rausch (`#FF385C`) as the only accent, near-black type with tightened
tracking, 12pt photo cards, line-icon category rail, floating capsule controls,
and sticky bottom action bars.

## Running it

```bash
open CityTourist.xcodeproj
```

Build and run on any iOS 18+ simulator. Without an API key it runs on bundled
sample data for Lisbon, Kyoto and Mexico City. With a key (below) you can search
and plan a trip to **any city Google knows**.

## Live Google Places data

The app pulls real places — names, ratings, review counts, price levels,
photos and **today's opening hours** — from the Google Places API (New) as soon
as a key is present.

1. In the [Google Cloud console](https://console.cloud.google.com/), create a
   project, enable **Places API (New)**, and create an API key.
2. Restrict the key to the Places API, and to your bundle id
   (`com.example.CityTourist`) under iOS app restrictions.
3. Copy the template and paste your own key into the copy:

```bash
cp CityTourist/Resources/Secrets.example.plist CityTourist/Resources/Secrets.plist
```

Open `CityTourist/Resources/Secrets.plist` and replace `PASTE_YOUR_KEY_HERE`.
`Secrets.plist` is gitignored, so the key never lands in source control. If you
would rather not keep a file, set `GOOGLE_PLACES_API_KEY` in the scheme's
environment variables instead.

Relaunch, and the Explore header reads **"Live from Google Places · updated
today"**. Without a key it reads "Sample places" and everything still works.

### What it costs

- **City search** uses Autocomplete, debounced 280ms, with a session token
  shared across the keystrokes and the one Place Details call that follows —
  so a whole search bills as a single session.
- **Each city load** issues six Nearby Search calls (one per category, 20
  results each), cached for the rest of the day; pull-to-refresh forces a
  refetch.
- **Reopening a trip or the Saved tab** after a relaunch issues one Place
  Details call per place not already loaded this session. Only place ids are
  stored on disk — Google's terms allow keeping an id indefinitely but not the
  rest of a place — so details are fetched again on demand. Anything today's
  Explore feed already loaded costs nothing extra.
- **Photos** bill per image loaded. Each is kept in memory for the session,
  so scrolling back past one doesn't fetch it again.

Field masks are kept to exactly what the UI renders, in
`GooglePlacesService.placeFields`, shared by Nearby Search and Place Details.
To cut cost during development, lower `maxResultCount` in
`nearby(city:category:)`.

## What's built

Every must-have in the brief, plus three of the four nice-to-haves:

| Brief | Where |
|---|---|
| Pick a city and dates to start an itinerary | `CitySearchView`, `SearchSheet`, `NewTripView` |
| Browse attractions, restaurants and activities | `ExploreView`, `PlaceCatalog` |
| Add places to a day-by-day schedule, reorder and edit | `AddToItinerarySheet`, `TripDetailView`, `ReorderStopsSheet`, `StopEditorSheet` |
| See the day's stops on a map | `ItineraryMapView`, `CityMapView` |
| Share via link, social, or named collaborators | `ShareTripSheet`, `GuestItineraryView` |
| Sign up / log in, trips saved across sessions | `SignInSheet`, `AppStore` persistence |
| *Nice-to-have:* bookmarks before scheduling | `SavedView` |
| *Nice-to-have:* collaborators with view/edit permissions | `ShareTripSheet` |
| *Nice-to-have:* per-stop reminders | `StopEditorSheet`, `AppStore.syncReminder` |
| *Recommended:* weather alongside the daily plan | `WeatherService`, `WeatherStore`, `TripDetailView` |
| Travel time between consecutive stops | `RouteService`, `RouteStore`, `TravelNote` |
| Warning when a stop falls outside opening hours | `WeeklyHours`, `HoursNote` |
| Fixing a day: the order that fits hours, travel and daylight | `DayPlanner`, `FixDaySheet` |
| Where you're staying, as each day's start and end | `LodgingSheet`, `Trip.lodging` |
| On the day: next stop, when to leave, running late | `TodayView`, `RunningLateSheet`, `LeaveBy` |
| Street-level preview of a place | `LookAroundBlock` |

Out of scope per the brief: bookings, payments, and group chat.

## Weather

Each itinerary day shows its forecast — on the day rail, so you can see the
whole trip at a glance, and in full under the day heading. When a day is wet
and most of its stops are outdoors, the itinerary says so and offers to find
something indoors.

Forecasts come from [Open-Meteo](https://open-meteo.com), which needs **no API
key and no signup**. The brief suggests OpenWeatherMap; Open-Meteo covers the
same ground for free, which keeps the project to a single key to manage.
Swapping providers means reimplementing `WeatherService` alone — nothing above
it knows where a `DayForecast` came from.

Each day also carries its sunrise and sunset — the same call, two extra fields.
An outdoor stop that runs past sunset says so ("ends after sunset", "after
dark"); indoor and nightlife stops never do, because a bar at 22:00 is the
point and a viewpoint at 22:00 is a wasted trip.

Two things worth knowing: forecasts only reach about 16 days out, so a trip
booked further ahead shows nothing rather than failing (and a long trip is
clamped to the horizon instead of the whole request being rejected); and
temperatures follow the device locale, so US devices get Fahrenheit.

## Travel times

The line between two stops now says how long the hop takes and whether the
plan allows for it — "13 min walk · 47 min spare", or "24 min drive · 14 min
short" in red when it doesn't. It replaces the line that used to just report
free time, so the timeline gained information without gaining UI: it stays grey
until something needs attention.

Estimates come from `MKDirections`, which is free and needs no key. Walking is
preferred; anything over 40 minutes on foot is quoted as a drive instead. Legs
are fetched one at a time (MapKit throttles bursts) and cached per pair, and
pairs it can't route — across water, or too far — fall back to the old free-time
line rather than implying a walk.

## Opening hours

A stop planned for when its place is shut says so, in the same red line as
the weather and travel warnings: "closed on Mondays", "not open until 10:00",
"closes 18:00, before you arrive", or "closes 18:00, before you leave" when the
visit runs past closing. The same check appears in the add and edit sheets
while the time can still change, so a clash shows before the stop is saved.

It uses the place's regular weekly hours (`regularOpeningHours`, the same
billing tier as today's hours, which were already fetched), so it works for a
trip months out — but holiday closures aren't covered. Each opening is stored
as minutes from Sunday 00:00, so a bar open Friday 20:00 to Saturday 02:00 is
one span, and one that runs past Saturday night wraps into the next week.
Sample places carry no hours, so the check only appears with live data.

## Fixing a day

When the timeline is warning about something — a place shut on arrival, a
visit cut short by closing time, an outdoor stop in the dark, a hop there isn't
time for — a banner offers to fix the day. The sheet shows the proposed day
against the planned one, old times struck through, and applies it in one tap.

`DayPlanner` keeps the day's time slots and decides which stop takes which. A
stop starts at its slot unless you couldn't be there yet, or the place opens
within 90 minutes, and then it's pushed later — never earlier, so a lunch slot
or a sunset slot survives. Orders are scored on what would go wrong first and
on travel and delay second, with three rules that keep it from being clever at
your expense:

- **Moving a stop has to be worth it.** Leaving its slot costs a stop as much
  as 15 minutes of travel, so a day that works isn't reshuffled to save a few
  minutes of walking.
- **Meals keep their time.** A food stop costs more to move the further it
  drifts, so breakfast doesn't end up at three in the afternoon because it's
  on the way.
- **A place shut all day stays put.** No order opens it, so the sheet offers a
  day of the trip when it is open instead.

Every order is tried up to nine stops (about 20 ms in a debug build), with any
order already worse than the best abandoned partway; longer days improve one
swap at a time. Scores are whole numbers, so ties are exact and your order wins
them. Hops use MapKit's times where the app has measured them and a
straight-line estimate otherwise, and where you're staying shapes the order:
the day leans towards starting and ending near it. Rain isn't weighed — the
forecast is daily, so no order is drier than another.

## On the day

When one of a trip's days is today, the Trips tab leads with it: the next
stop, when to leave for it, and a row of dots for the day. The Today screen
opens with a strip of the whole day — stops spaced by time, ticked off as
they're done, the current one highlighted, and a marker for how far along a
hop you are — then the detail: the stop you're at, the next one with **"Leave by 1:10 PM · leave in 32 min"**, its
hours and daylight warnings, directions in Apple Maps, and the rest of the
day. The leave-by time comes from MapKit and your location if you've allowed
it (only asked when you tap *Use my location*), otherwise from the stop before
or where you're staying.

**Free time.** When there's an hour or more with nothing planned — between
stops, or once the plan is done — a card offers a few places that fit:
open then, close enough to get there, see it and still make the next stop,
nothing outdoors in the dark or the rain, and no bars before six. One tap
drops a place into the gap. When nothing fits, the card doesn't appear.

**Running late?** Pick how far behind you are and the planner re-times the
rest of the day: gaps absorb the delay where they can, so only the stops that
have to move do, and a place that would now be shut can swap ahead of one that
won't. *Keep my order* turns the swapping off. Applying it — or a fixed
day — shows "Day updated · Undo" for a few seconds, since several times
changed at once; any later edit to the day lets the undo lapse.

Reminders now fire when it's time to leave the stop before (or where you're
staying) rather than a fixed half hour ahead, and are rescheduled whenever
anything on the day changes. They're scheduled ahead of time, so the hop is
the straight-line estimate rather than a MapKit route.

## Look Around

A place's detail screen shows Apple's street-level view above the map, tappable
into the full immersive viewer. It's `MKLookAroundSceneRequest` plus
`LookAroundPreview` — free, no key.

Coverage is real and patchy: verified live, San Francisco, London and New York
all return a scene while Lisbon returns nil. When there's no scene the block
renders nothing at all and the detail screen keeps the map it already had, so
absence looks deliberate rather than broken.

Two traps worth knowing, both of which silently produce "no coverage here":

- The lookup must not hang off a view that starts empty. Attaching `.task` to a
  `Group` that renders `EmptyView` until the scene arrives means the fetch may
  never fire at all — lifecycle on a view with no layout presence is not
  reliably run. The block keeps a zero-height `Color.clear` instead.
- The scene request must be held for the whole `await`. Created inline as a
  temporary, ARC can release it mid-flight and the scene comes back nil.

In DEBUG builds the block prints "no street view here" when a lookup finishes
with no scene, so a genuine coverage gap is distinguishable from a bug.

## Sharing and the web viewer

`web/index.html` is a single self-contained page — no build step, no backend,
no dependencies. Deploy it anywhere static:

```bash
# GitHub Pages: commit web/ and enable Pages, or
npx netlify-cli deploy --dir=web --prod
```

Then set `ShareBaseURL` in `Secrets.plist` to the deployed URL. Share links are
built against it.

**The itinerary travels inside the link.** It's base64url-encoded JSON in the
URL *fragment*, which has two consequences worth knowing:

- It works with no server and no accounts — anyone can open it on any phone or
  desktop, and the page renders it entirely client-side.
- A fragment is never sent to the host, so the plan stays out of server logs.

Trade-offs, and why the next stage exists: the link is a **snapshot**, so
editing the trip afterwards doesn't update a link you already sent; there are
no photos, because Google Places photo URLs need the API key and that can't go
in a public page; and a very large itinerary makes a long URL. A normal trip
encodes to roughly 1–3 KB, but past ~8000 characters the share sheet warns that
some apps may truncate it. `ShareLinkTests` pins the exact JSON keys the page
reads, so renaming a field fails a test instead of silently producing a blank
page.

Deliberately no compression: a realistic trip is small enough that plain base64
is fine, and it means the page decodes with `atob` in every browser rather than
depending on `DecompressionStream` (Safari 16.4+).

## Tests

```bash
xcodebuild test -project CityTourist.xcodeproj -scheme CityTourist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

145 tests in eleven suites, all offline — the Places suite runs against a
`URLProtocol` stub, so it exercises real request construction, HTTP handling,
decoding and model mapping without spending API quota.

| Suite | Covers |
|---|---|
| `PlacesAPITests` | Nearby search mapping, field-mask scope, category/price mapping, dedupe across the six category calls, HTTP errors, autocomplete, city details, the iOS bundle-id header, weekly hours (including round-the-clock and past-Saturday-night openings), place details by id, restoring places after a relaunch (only unknown ids fetched, failures retried, no-key path, nearest city for legacy bookmarks), and the Monday-vs-Sunday weekday conversion for opening hours |
| `AppStoreTests` | Day generation per date range, time-ordered stops, reorder semantics, deletion, missing-trip safety, share links, collaborators, reminders timed for leaving the stop before or the hotel, following a reorder and cancelled with their trip, retiming a day, undoing a re-planned day, moving a stop to another day, suggesting a time on today that hasn't passed, finding today's trip, lodging surviving a relaunch, persistence round-trip including each bookmark's city, and loading state written before city search existed |
| `CatalogTests` | Sample-data fallback with no API key, place resolution for both bundled and live places, nearest-city matching, test-host detection, open-status and duration formatting |
| `TravelTests` | Spare/short arithmetic, overlapping stops, walk-vs-drive wording, sub-minute rounding, the no-estimate fallback, and overlapping day lookups both loading |
| `WeatherTests` | Forecast-horizon clamping, out-of-range trips, locale units, column-oriented decoding with null days, WMO code interpretation, and which categories count as outdoors |
| `ShareLinkTests` | Snapshot flattening, dropped unresolvable places, base64url round-trip with accents, URL-length guard, and the wire-format contract the web viewer depends on |
| `DaylightTests` | Sunrise/sunset parsing in the destination's timezone, malformed values, and the exact boundary at which an outdoor stop is flagged |
| `OpeningHoursTests` | Closed days, arriving before opening or during a break, closing before you arrive or leave, exact boundaries, nights past midnight and past Saturday, round-the-clock places |
| `DayPlannerTests` | Leaving a working day alone, trading slots to beat closing time, waiting for an opening, closed-all-day stops kept in place, daylight, shorter routes only when worth it, meals holding their time, the hotel shaping the order, running late, and exact search up to nine stops |
| `FreeTimeTests` | The next hour or more with nothing planned (between stops, past overlaps, after the plan's done, not late at night), and which places fit it: near first, only what fits before the next stop, not shut, not already planned, not outdoors in the rain, no bars before evening |
| `TodayTests` | The done, current, next and later stops at any time of day, leave-by times with their grace and countdown wording, and the day strip's spacing, scrolling and "now" position |

`PlacesAPITests` is marked `@Suite(.serialized)`: `URLSession` instantiates
`URLProtocol` subclasses itself, so the stub's canned response has to live in
static state, and running those tests in parallel hands them each other's
fixtures.

## Structure

```
CityTourist/
  App/            entry point and tab bar
  DesignSystem/   palette, type ramp, cards, chips, photography
  Models/         Place, Trip, ItineraryDay, ItineraryStop, Collaborator
  Data/           Google Places client, place catalogue, sample data, secrets
  Store/          AppStore — trips, saved places, account, persistence
  Features/       Explore, Place, Trips, Map, Saved, Profile, Share
```

## Notes on the current build

- **Auth is mocked.** The brief calls for Google and Apple SSO with email as a
  fallback; `SignInSheet` lays out those three entry points but signs in
  locally. Wiring real SSO needs `AuthenticationServices` and a backend.
- **Persistence is local**, to a JSON file in Documents. "Across devices" needs
  the sync backend the brief anticipates. Stops and bookmarks store a Google
  place id only, so after a relaunch their details need a connection: offline,
  a restored trip shows those stops as "Couldn't load this place" with a retry.
- **Collaborative editing is single-device.** Collaborators and permissions are
  modelled and editable; live multi-user editing needs the backend too.
- **No Live Activity yet.** The next stop and leave-by time would suit the
  lock screen, but that needs a widget extension target, which is best added
  in Xcode (File › New › Target › Widget Extension).
- **Offline** is a per-trip flag today — itinerary data is already local, so
  what remains is caching map tiles and Places photos.
- **Photos** fall back to a deterministic mesh gradient seeded off the place id
  whenever there's no Google photo, so cards never show a broken image.
