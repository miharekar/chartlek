# Token efficiency

Respond like smart caveman. Cut all filler, keep technical substance.

- Drop articles (a, an, the), filler (just, really, basically, actually).
- Drop pleasantries (sure, certainly, happy to).
- No hedging. Fragments fine. Short synonyms.
- Technical terms stay exact. Code blocks unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Applies to chat replies only; PRDs, PR descriptions, commit messages and drafted comments use normal prose.

# Chartlek

This file provides guidance to AI coding agents working with this repository.

## What is Chartlek?

Chartlek is a local, single-user Rails app. It caches the owner's Garmin Connect running history in SQLite and rebuilds the charts of Smashrun (an abandoned running-stats site) with Tailwind and D3. `docs/PRD.md` is the product spec (features, formulas, data model, sync); `README.md` describes the features for humans. Update the PRD and this file in the same change as the code.

## Development Commands

```bash
bin/setup              # install gems, prepare DB, clear logs/tmp, start bin/dev unless --skip-server
bin/dev                # Rails server on PORT (3000 default), Tailwind watcher and Herb dev server
bin/rails activities:sync    # incremental Garmin sync, foreground
docker compose up -d --build   # build and (re)start the production container on port 9295
docker compose logs -f         # production logs (Puma, Solid Queue, the hourly sync)
bin/rails activities:resync  # full resync, deletes Garmin runs missing upstream
bin/rails activities:download   # fetch and process Garmin originals for runs lacking one
bin/rails activities:reprocess  # rebuild tracks and metrics from stored originals
bin/rails activities:hr_zones  # per-run HR zones: FIT originals, estimate for the rest; prints counts by source (seconds, no network, idempotent; run activities:bands after it)
bin/rails activities:bands   # compute activities.bands from every stored track (seconds, no network)
bin/rails wellness:backfill  # Garmin wellness history from the first run, newest first, 1 request/s, resumable (DAYS=30 limits it, ONLY=sleep limits the metrics, an unknown name aborts); prints counts only
bin/rails smashrun:fetch     # pre-Garmin runs: match, fill calories and races, attach recordings (15 s per request)
bin/rails weather:fetch      # Open-Meteo weather backfill
bin/rails garmin:probe       # read-only Garmin endpoint probe: statuses and JSON shapes, never values; writes OUTPUT= (default under the system tmpdir, mode 600); SCOPE=all adds the first round's candidates
bin/rails strava:fetch       # gap fill from the Strava API (needs the Connect Strava nav button clicked once)
bin/rails "strava:import[/path/to/unzipped/strava/archive]"  # gap fill from a Strava archive
bin/rails test         # full Minitest suite
bin/rails test test/models/activity_test.rb     # single file
bin/rails test test/models/activity_test.rb:12  # single test by line number
node --test test/javascript/*_test.mjs   # JS helper tests
bin/rubocop            # rubocop-rails-omakase baseline
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/ci                 # CI pipeline (setup, style, security audits, tests, seeds)
```

Development URL: <http://localhost:3000>

## Architecture Overview

### Activities, sync and originals

- Data lives in SQLite (`storage/`).
- `Activity` is one run, keyed by `(source, external_id)` with `source` `garmin`, `strava` or `smashrun` (only one Smashrun-only run, before Garmin; it has no `garmin_url` or `strava_url`). Class-scoped concerns fill it in: `Activity::GarminSync`, `StravaImport`, `StravaLink`, `StravaGear`, `SmashrunImport`, `TrackProcessing`, `Weather`, `Browsing`, `Performance` (VDOT, `grade_adjusted_pace` from the summary's `avgGradeAdjustedSpeed`, `garmin_pr?` from its `pr`, `workout?` and `workout_splits` from its `INTERVAL_*` splits), `HrZoning`, `Physiology`. `Activity.listed` drops `summary` but selects `json_extract(summary, '$.pr') AS garmin_pr` and a `garmin_workout` EXISTS over `splitSummaries` for the list's PR and workout chips. `Activity.listed`, `Overview.for` and `PrProgress.for_all` also leave `bands` and `hr_zones` out.
- `has_one_attached :original` (Active Storage, local disk): the Garmin ZIP as downloaded, or the gzipped Smashrun detail `smashrun-<id>.json.gz`. `process_original` parses it (`Track::Fit`, `Track::Tcx`, `Track::Smashrun`) into the `tracks` table and the `splits`, `pace_variability`, `hr_zones` and `bands` columns. `weather` (JSON) comes from Open-Meteo.
- `Notables.for(activity, runs)` is computed on the fly (needs `weather` loaded; no column) and rendered as `chip(…, :notable)` pills in `runs/_notables`. `Food.for(calories)` picks the food equivalent.
- Sync (`Activity::SyncJob` hourly via `config/recurring.yml` in production, and the Sync now button through `Activity.sync_later`; `bin/dev` syncs only on the button; opening a page never syncs):
  - downloads the original of every run it pages through that has none;
  - processes a run that has an original but no track (so a failed download or parse is retried by the next sync);
  - reprocesses a run whose `started_at`, `timer_s` or `distance_m` changed (picks up trims; other summary changes don't matter to `process_original`);
  - refreshes `Profile#sync_started_at` after each run (`Profile#sync_progress`), so a long sync keeps counting as running past `SYNC_STALE_AFTER` and a second sync doesn't start in parallel;
  - fetches weather for every run up to 60 days old that lacks it (forecast API for the last 5 days, archive for older runs);
  - a failure for one run is logged and skipped.
  - the live status: `SyncsController#create` answers Turbo with a `turbo_stream` replace of `#sync_status` (queued "Syncing…", never touching `Profile`); `sync_now` and `Activity::StravaLinkJob` broadcast `broadcast_refresh_to(:garmin_sync)` when runs, links or gear changed; the `relative-time` controller ticks the `<time>` and `live-refresh` on `<body>` refreshes the page when the `garmin_sync` stream reconnects after a drop, unless a form field is on the page (rules in `helpers/live_refresh.js`).
- `Profile` is a singleton (`Profile.instance`): Garmin profile settings and sync state (`synced_at`, `sync_started_at`, `sync_error`), the Strava connection, `hr_zones`.
- `started_at` is true UTC. `local_started_at` is the run's local wall-clock time stored as-is. `config.time_zone` stays UTC so `local_started_at` is never shifted; use it for all day bucketing (streaks, weekdays, AM/PM, calendars).
- Integration wrappers live in `app/lib` (autoloaded): `Garmin::Client`, `Strava::Client`, `Smashrun::Client`, `OpenMeteo::Client`.
- FIT parsing is our own decoder, no gem (`fit_kit` 0.4.0 doesn't build on Ruby 4.0.9). `Track::FitFile.read(bytes, wanted, arrays = {})` walks the file once and unpacks only the wanted integer fields of the wanted messages: `wanted` is `{global => [field numbers]}`, the result `{global => [{field => value}, …]}` in file order. Values are raw integers (the base type's invalid value is nil), so `Track::Fit` applies scale, offset, semicircles and the FIT epoch, in the order that keeps floats bit-identical to the old parser. A field returns an array only when `arrays` declares it (`{global => [field numbers]}`; only the zone message 216 fields 2 and 6); any other wanted field with more than one element, a string, a float or an odd size reads as nil, so `Track::Fit` raises its usual `Track::Error` or drops the value. No CRC checks, only the first segment is read, and a compressed timestamp header is framed as a data message but gives no timestamp, so such a record raises "FIT record has no timestamp" (no stored file has one). Bounds checks make every malformed file a `Track::Error`. 5.6 ms a file at p50, about 12 ms in the app.

### Tracks

- `tracks.data` is columnar JSON `t, d, lat, lng, alt, hr, cad`, at most 2,000 points. `Track#route` is `[lng, lat]` pairs, `Track#route_distances` is parallel to it, `Track#bars(100)` gives the 100 m bars for the speed chart and pace variability wheel.
- FIT recordings are clipped because originals are untrimmed: records before `started_at` (−2 s) are dropped and the rest rebased, then records whose timer time exceeds `timer_s` (+2 s) are dropped. Don't clip to `started_at + elapsed_s`: Garmin's `elapsed_s` can be shorter than the file's wall-clock span on runs with long pauses and cuts real data.
- TCX isn't clipped: `Track::Tcx` keeps no per-row timestamps, and `Track::Recording#clip` only clips rows with `:at`. `Track::Tcx` removes pauses per lap instead: the lap's excess (the time the lap adds to `t`, namely its own gaps plus the gap into its first trackpoint unless that is over 10 s, minus `TotalTimeSeconds`) is taken out of stall gaps (over 10 s, distance advancing under 0.5 m/s), largest first. Gaps where distance keeps advancing are kept, as in the sparse treadmill files. Garmin's `timer_s` for these imports equals the sum of the laps' `TotalTimeSeconds`.
- If the distance series is missing or more than 10% off `distance_m`, `d` is rebuilt at constant pace and `splits`, `pace_variability`, `chart_metrics` and `bands` are nil. The run page omits the speed chart (it renders only when `splits` is present), because identical bars mean nothing.
- Zero cadence and zero heart rate are missing values for every format (`Track::Recording` turns them into nil), so cadence ranges, axes and split averages reflect running only.
- Smashrun marks samples without a GPS fix with `latitude` = `longitude` = −1.0 (other series stay valid). `Track::Smashrun` turns the pair into nil lat/lng.
- Smashrun `clock` includes stopped time. After the distance is settled, `Track::Recording#without_stops(timer_s)` removes the excess of `t` over the row's `timer_s` from stopped intervals (distance advancing under 0.5 m/s), largest first and never more than the excess; final `d` is unchanged. It applies to every non-Garmin row except rebuilt distances and leaves tracks shorter than `timer_s` alone. `timer_s` is the budget, not the detail's own `duration`.
- Per-split gain and loss are the sums of the `Track::Elevation` 100 m bins (1 m hysteresis carried across bin and km boundaries); a split with no known bins has nil gain and loss. Totals can differ from Garmin's by a few percent, and single runs by tens of metres.
- `tracks.chart_metrics` (nullable JSON) is set by `process_original` from the full-resolution recording, before downsampling: `elevation` (the bins) and, for `workout?` runs whose FIT laps carry intensities, `steps` (`Track::Steps`: `[{type, from, to, time}]` in metres and seconds, laps mapped warmup/active/recovery/rest/cooldown keyed by the raw FIT intensity enum in `Track::Steps::TYPES` (0 active, 1 rest, 2 warmup, 3 cooldown, 4 recovery, 5 interval as active), consecutive warm-up and cool-down laps merged, at least two different types or it is auto-laps). The whole column is nil when the distance is rebuilt; without altitude only `elevation` is nil. The `pace-variability` wheel (`helpers/pace_variability.js`) is one wedge per whole 100 m of `Track#bars`, not from `chart_metrics` (older rows may hold an unused `speed_windows`).
- Known data (tests and data would otherwise look broken):
  - 2017 iSmoothRun treadmill TCX imports have sparse trackpoints and inconsistent Garmin summaries (`1757716207`: track `t` 2,501 s against `timer_s` 2,830). Other TCX outlier: `1757715300` (last lap's samples stop 80 s early).
  - Garmin runs `3843370908` (summary edited on Garmin to 3,000 m more than the file holds) and `8547425833` (records end at 10,998 m, summary says 17,202 m) have rebuilt distances, so no `splits`, `pace_variability` or `bands`.
  - Smashrun `6093331` and `5850866` have null recordings and raise `Track::Error: Smashrun activity has no recording`, so those two Strava runs have no track.

### Pace zones and the run page

- `PaceZones` holds the 37 fixed zones; colours are `--pace-zone-0` to `--pace-zone-36` in `app/assets/tailwind/application.css`, mixed from six `--pace-stop-*` variables that differ for light and dark. Formulas for the performance zone and strip range are in PRD §5.
- The run tile grid's spans change only at `lg` and are picked from whether pace variability and elevation (altitude or gain) exist, so every combination packs without gaps; keep that when adding a card. There is no separate Elevation tile.
- The run page shares one distance cursor (`helpers/run_cursor.js`; the Wellness page reuses it with epoch ms of the day). Subscribe in `connect` and unsubscribe in `disconnect`, or charts leak handlers across Turbo visits.
- Analyze Run (`analyze-run`): this run (`training_point`) is never part of the averages. The brush overlay sits above the dots, so dot hover and click are hit-tested in the controller, which rebuilds only when the width changes.
- The speed and profiles charts draw `track.steps` through `helpers/workout_steps.js` (`drawSteps`: strip, tint, HR dividers; colours are `--step-*`). Keep the strip centre well over 10 px from the plot overlay: Chrome touch targeting otherwise gives the pointer to the overlay.
- `show.html.erb` computes `HrZones.for(@run)` once, only for runs with HR, and hands it to `_profiles` and `_physiology`. The HR line's zone gradient lives in the chart's svg with a per-instance id (`hr-line-<n>`) so a redraw or `disconnect` removes it.

### Per-run HR zones

- `activities.hr_zones` is JSON `floors`, `max_hr`, `seconds` and `source` (`fit` or `estimated`). Garmin's zones move with resting HR: never use today's zones for an old run.
- `HrZones#zone(bpm)` is nil below zone 1; `HrZones#range(zone)` is the bpm range. `HrZones.for(activity)` builds the run's zones and falls back to `HrZones.current` (Garmin's running zones from `profiles.hr_zones`, else the default 50/60/70/80/90% bands of the highest recorded `max_hr`) for any run with no stored zones (in practice, runs without HR).
- `Track::FitZones.read(bytes)` reads the session `time_in_zone` message (216 fields 0, 2, 6) through `Track::FitFile`. It never raises: a truncated or corrupt file, or a message that doesn't fit, reads as nil, so the run falls through to the estimate. An undefined sixth floor (255) is kept as `max_hr` 255, as stored runs have it; an undefined floor among the first five or an undefined seconds value fails validation. Tests hand-build the message (`fit_zones_test.rb`, `hr_zoning_test.rb`); `test/support/fit_builder.rb` writes FIT bytes from `[global, {field => [base_type, value]}]` for the track tests.
- `Activity::HrZoning#derive_hr_zones` decides floors and seconds independently (FIT when valid, else estimate for floors; FIT when any is positive, else the track via `HrZones#seconds` for seconds, which skips below-zone-1 and missing HR, unlike `Track::Bands`). Zones are stored for every run with floors, even with all-zero seconds, so charts and bands always use the run's own floors.
- The estimate is the per-floor median of the `ESTIMATE_FROM` (100) FIT sets nearest before the run, so a later run without a zone message gets zones of its own time, not 2017's.
- `process_original` sets it. `Activity.backfill_hr_zones` (`activities:hr_zones`) writes with `update_column`, including the FIT result `nil` so stale rows clear, and is idempotent. Run `activities:bands` after it.

### Strava gear (read-only, never written)

- `activities.strava_gear_id` is updated on every link scan (null = no gear); `strava_id` itself is never overwritten. `Activity belongs_to :gear` by value with no FK (ids can precede rows). `gears.model` holds Strava's `model_name`, which Active Record reserves; `retired` is false unless the payload says true.
- Only runs with `strava_id` have gear. Gear tags and the header's gear line show only once `Profile#strava_gear_ready?` (access and a first full scan), so no run shows an amber No gear before it. `Profile#strava_gear_access?` (from `profiles.strava_scope`) gates every gear request; the nav shows Reconnect Strava without `profile:read_all`.
- One job refreshes the Strava token at a time: each Garmin sync queues one `Activity::StravaLinkJob`, which links and then runs the gear pass (`sync_strava_gear_after_link`). Don't add a parallel gear job.
- The hourly gear pass is the recent one (last 30 days), or the full one while `strava_gear_synced_at` is nil and `Profile#strava_gear_scan_due?` (fewer than `Profile::STRAVA_GEAR_ATTEMPTS`, 2, failures in `strava_gear_attempts`). Every failed full pass (a `Strava::Client::Error` other than `NotConnected`, or an open/read timeout) adds one; a successful full pass or a reconnect resets it. Without the cap a gear that always fails costs about 500 requests a day.
- A gear-step failure in the link job is rescued (class logged, links already saved). The Refresh button's `StravaGearJob` still raises and never stamps `strava_gear_synced_at`.
- `Activity.sync_strava_gear_later(full: true)` is the Refresh path. A dev server needs `bin/rails tailwindcss:build` after new classes.

### Wellness

- Never log or print wellness values: the `WellnessDay` columns (the `sleep_` prefix too) and `raw` are in `config.filter_parameters`, which Active Record also uses for SQL binds.
- `Wellness::Sync` (`refresh` hourly via `Wellness::SyncJob`, independent of `Activity::SyncJob`; `backfill(from:)` in 30-day chunks):
  - Null fields never overwrite stored values.
  - An empty summary day gets a row with `raw["summary"]` = `{}` as a marker. The backfill skips stored summary days and final markers (final once `updated_at` is over `MARKER_FINAL_AFTER`, 7 days, past the date); a younger marker is fetched again and touched when still empty.
  - A source stops after `STOP_AFTER` (6) empty chunks; a chunk's emptiness counts the data days it holds, so a resume past many stored chunks still reaches older days.
  - A day is found first, otherwise created, rescuing the unique-date conflict to use the winner's row, so a refresh and a backfill racing on one date update the same row.
  - `Garmin::Client#get` returns nil for an empty body (HRV 204). Weight arrives in grams. A night with no values or no date is skipped; `sleepTimeSeconds` 0 is stored as missing and all four stage values are dropped when deep, light and REM are all 0. The stress and Body Battery range endpoints are not called.
- Wellness page: the payload is dense (`null` for missing days, all-null series left out), so lines break at gaps. The right margin is 44 px on every chart so the shared x scale and the day cursor line up; keep it when adding a chart. A spec with `secondary` (Sleep's score) gets a second y scale.
- `Wellness::Trends` reads `sleep_need` (seconds) from `raw["sleep"]["sleepNeed"]["actual"]` (minutes) with a `json_extract` entry in `SERIES`, inside the one `pluck`; no column.
- `sleep_bed` and `sleep_wake` (the `timing` chart) are seconds from the wake date's midnight, computed in SQL from `raw["sleep"]["sleepStartTimestampLocal"]`/`sleepEndTimestampLocal` (local wall-clock epoch ms) minus `strftime('%s', date)`, and `sleep_in_bed` from the `...GMT` pair (the local difference is an hour off on DST nights); all three are NULL when the local wake day isn't the row's date (`WOKE_ON_DATE`), so such a night is a gap. The y axis is inverted so the evening before is at the top, and `clockLabel` (`helpers/wellness.js`) formats offsets.
- Pace Trends overlay: `overlay` (`rhr`, `hrv`, `sleep`) must stay in `PaceTrendsHelper::CARRIED_PARAMS` and `syncUrl` (dropped when None); the series are in the payload so switching is client-side; `this.margin` widens the right side only when overlays exist.

### Training Bands

- `activities.bands` is set by `process_original` and backfilled by `Activity.backfill_bands` (`activities:bands`, after `activities:hr_zones`); runs with nil `splits` are skipped, and an array with no time is nil. `Track::Bands` uses each run's own `HrZones.for(run)`.
- `TrainingBands` sums per Monday week in Ruby from one `pluck`; `PACE_GROUPS` are fixed zone ranges.
- The `training-bands` controller's Stimulus actions are `changeCategory` and `changeView`, because `category` and `view` are instance fields that a same-named method would shadow. `from`, `to`, `category` and `view` are URL params; filters are kept per category in memory.

### Goals

- `Goal::Progress` formulas are in PRD §5. `Goal#progress(today:, activities:)` queries the period plus the 28 days before today when no activities are given. `open_today?` (today has no run yet) makes the expected distance count days through yesterday, so a goal isn't red from the first hour of the day.
- `Overview#goal_tiles` is the `GoalSlot`s (goal plus progress) that have a goal: all time the current year's then the current month's, a year or month page its own. `overviews/_goal_tile` renders each in the stats grid with `goal_tile_span` (`col-span-2`, or `col-span-2 lg:col-span-1` for two), and Kilometers run is `lg:col-span-4` when there are none, so the 4-column grid never has a gap. `Overview#goal_to_create` is an unsaved `Goal` for a year or month page without its goal (never all time): the Kilometers run tile and the empty state link to `new_goal_path` with it. `selectable_months` always includes the current month; visibility rules are in PRD §4.10.

### Pro Map

- The page redirects to the run without a route or a public Mapbox token.
- The map source merges consecutive same-colour segments into one LineString, because geojson-vt drops 3 m features at low zoom.
- `Track::Efforts` is computed on the fly (nothing stored) and approximate on long runs, since tracks keep at most 2,000 points.
- Pace needs `splits`, HR needs `HrZones.for`, grade needs `alt`; metrics a run lacks are left out. The change-in-pace graph reuses `helpers/run_cursor`, so hovering it moves the map marker.

### Frontend, charts and theme

- Frontend is Importmap + Stimulus + D3 + Mapbox GL JS with no Node build. Pins live in `config/importmap.rb`; d3 and Mapbox GL JS are vendored in `vendor/javascript`.
- `lg` is 56rem (`--breakpoint-lg` in the `@theme` block), so the iPhone Duo's open landscape (951 px) counts as desktop while its portrait (669) stays 2-up.
- Theme is Tailwind with zinc neutrals and a lime accent, switched by `<html data-theme="system|light|dark">` (`ThemesController`, a permanent `theme` cookie, a full-page redirect). Tailwind's `dark:` variant is a `@custom-variant` on that attribute. Chart colours are `--chart-*` CSS variables in `app/assets/tailwind/application.css` (`accent`, `accent-highlight`, `accent-low`, `highlight` amber, `muted`, `grid`, `axis`) that switch with the same rule, so D3 code uses them directly (`fill: var(--chart-accent)`) with no JS for theme changes. Never use `light-dark()`: `getComputedStyle` returns it unresolved, and the map reads these values.
- Every chart click opens the run page in the same tab (no external links from charts). Pages call `turbo_exempts_page_from_cache`, because charts draw on `connect`, and render an empty state instead of charts when there are no runs.
- Chart controllers get server-rendered JSON through Stimulus values. Refreshes after a sync use `turbo_refreshes_with method: :replace`, so controllers reconnect and redraw; charts must not rely on morphing.
- Time: `local_started_at` goes to JS as epoch ms (`local_started_at.to_i * 1000`), dates as `YYYY-MM-DD`. Parse with `parseTime` from `helpers/time`. Use only UTC d3/Date APIs (`d3.scaleUtc`, `d3.utc*`, `getUTC*`), never local-time ones.
- Escape interpolated names with `escapeHtml` before `showTooltip`. Title-and-rows tooltips use `tooltipHtml(title, rows, {heading})` (escapes everything); distances in them use `formatDistance` (one decimal, with thousands separators), never `toFixed(3)`.
- Hover charts wire their pointer handlers with `scrub` from `helpers/scrub.js` (`surface` for one overlay, `items` for per-datum shapes, `tap` for the Analyze Run strip whose brush owns touch drags), never bare `mousemove`/`mouseleave`, so a finger drag works like the mouse. It sets `touch-action: pan-y pinch-zoom` (pinch and zoomed-page panning stay available) on the owning `<svg>`, because Chrome ignores it on SVG shapes. Touch tooltips sit above the finger (`pointerPosition`). `noMouseFocus` stays on `mousedown`: a tap's compatibility mouse events still fire it. The Run speed brush is `touchable(false)`: a touch drag scrubs the cursor.
- Charts with thousands of nodes (the Overview scatter dots and heatmap cells) build that layer on a detached `create("svg:g")` and append it once, because Stimulus's MutationObservers otherwise process every node D3 adds. Call `scrub` after attaching, since it reads `ownerSVGElement`. A chart that only uses the width returns early from `observeSize` when it is unchanged, since a draw changes the height and fires the observer again.
- The four timeline pages (Pace Trends, PR Progress, Wellness, Training Bands) share one window block: the `application/_window_block` partial (range, hint, presets, taking the Stimulus identifier), `ControlsHelper#window_presets` (with `PRESETS`) and `helpers/presets.js`. The `createTimeline` default height of 72 px is used everywhere, under the chart card (Wellness keeps it above its charts). Each controller has a `preset` action, a `range` and `preset` target, and keeps `from` and `to` in the URL with `history.replaceState`.
- Overview hover selection goes through `helpers/linked_selection.js`: the scatter registers the canonical run list, each chart `publish`es on hover and `clearSelection`s on leave and `disconnect`, the others `subscribe` and only restyle their highlight layer.
- Predictions use the Ruby `Vdot.time_table` plus `predictTime` from `helpers/predictions`.
- Mapbox: every map is Mapbox GL JS, never Leaflet or another library; no imperial units, no toggle.
  - The single-file UMD build `vendor/javascript/mapbox-gl.js` (the `./esm` export is multi-chunk with relative imports, which Propshaft's digested paths break), pinned with `preload: false` and imported dynamically in the controller (about 1.9 MB, every controller is eager-loaded). It sets `window.mapboxgl`. Its CSS is `app/assets/stylesheets/mapbox-gl.css`, which draws the required logo and attribution.
  - Styles are `mapbox://styles/mapbox/light-v11` and `dark-v11`, chosen from `<html data-theme>` (and `prefers-color-scheme` under System, where an OS change calls `setStyle`). `setStyle` drops sources and layers, so add them again on `style.load`: `#drawTerrain` first (hillshade and contours below the roads, `peaks` before the first label layer so it has the lowest placement priority), then `#draw` adds the route and markers on top.
  - Paint properties can't read CSS variables: resolve `--chart-*` colours with `getComputedStyle` (`helpers/map_base.js` `resolveColor` goes through a canvas, since `--pace-zone-N` is a `color-mix()` Mapbox can't parse; `run-map` and `pro-map` both use it).
  - Every `Map` sets `performanceMetricsCollection: false`: GL JS 3.33 defaults it to on and sends the user agent, screen size and GPU to Mapbox (PRD §10 says no analytics).
  - `_map.html.erb` renders `MAPBOX_TOKEN` into the page as a Stimulus value and skips the whole map section unless the token is a public `pk.` one.
- The dev server binds 0.0.0.0 (`Procfile.dev`) and allows the hosts `framework:3000` and `test.rekar.eu`, behind Tailscale. No auth.

## Privacy

- Never print or log the Garmin key (`GARMIN_API_TOKEN`), the Strava secret (`STRAVA_SECRET`), the Strava access and refresh tokens (stored encrypted on `profiles`), `SECRET_KEY_BASE`, the Active Record encryption keys (`ACTIVE_RECORD_ENCRYPTION_*`), the Smashrun credentials (`SMASHRUN_USERNAME`, `SMASHRUN_PASSWORD`) or any access token, including the Smashrun token.
- Test fixtures must be synthetic: no real coordinates, activity names, IDs or health data from the owner's account. Never copy a downloaded original into `test/`.
- `MAPBOX_TOKEN` is a public (`pk.`) token rendered into run pages because the browser needs it for tiles. Still never print or log it, and never use a secret (`sk.`) token.
- `.env` and `storage/` stay git-ignored.
- `storage/dumps/` holds raw Garmin, Strava and Smashrun API dumps, smashrun.com page captures, audit reports and dev DB backups. It is the owner's personal data: never copy it into `test/`, never print it.

## Garmin Personal API

Verified against the real API (Oct 2026); the endpoint table is in PRD §6.1.

- Base URL `https://personal.connectapi.garmin.com`. `POST /personalapitoken-service/personal-api/personal-api-key/token` with `Authorization: ApiKey <key>` returns the bearer JWT as a `text/plain` body (not JSON); `exp` and `iat` are 24 h apart. Data requests use `Authorization: Bearer <jwt>`.
- Activity search: `activityType=running&start&limit`, newest first. `limit=100` works; `limit=250` returns HTTP 500, so use 100. It also returns `trail_running`; `treadmill_running` syncs with `indoor: true` (`INDOOR_TYPES`). `indoor_running` and `virtual_run` were never seen, so they are unverified. Unfiltered pages mix in cycling, swimming and hiking, so keep the filter.
- Field notes:
  - `startTimeGMT` and `startTimeLocal` are `"YYYY-MM-DD HH:MM:SS"` strings without zone. Parse both as UTC.
  - `averageHR`, `maxHR` and `calories` are floats. Cadence fields are `averageRunningCadenceInStepsPerMinute` and `maxRunningCadenceInStepsPerMinute`.
  - `eventType.typeKey` is `race` or `uncategorized`.
  - `vO2MaxValue`, `locationName` and `fastestSplit_*` are sometimes missing or nil.
  - A few "runs" have distance under 100 m; sync skips them.
  - Summaries carry `splitSummaries` and `hrTimeInZone_*` but no time series.
- Originals: `GET /download-service/files/activity/{id}` (same bearer auth, through `Garmin::Client#authorized_response`) returns a ZIP with one file: `<id>_ACTIVITY.fit` for watch runs, or `<id>_UNKNOWN.tcx` for the 2017 bulk imports. They are untrimmed (Garmin applies trims only to the summary): clip FIT records as in Tracks.
- Rate limits: no rate-limit or `Retry-After` headers. 1 request/s produced no 429s. `Garmin::Client` throttles to 1 request/s and backs off on 429, 5xx and transient network errors.
- Garmin Connect activity URL `https://connect.garmin.com/app/activity/:id` is verified.

## Deploy

- The app runs as a container, served at https://chartlek.rekar.eu from this machine: `docker compose up -d --build` builds the image (stock Rails 8.1 Dockerfile on `ruby:4.0.9-slim`, Puma on 3000 without Thruster, assets precompiled) and starts it on port 9295. Caddy on the Pi terminates TLS and proxies to it over Tailscale; on the LAN use `http://<host>:9295`. `docker compose logs -f` shows the logs, `docker compose ps` the state. `Rack::Deflater` (in `config/application.rb`) compresses every response, and assets are served `immutable`.
- Rebuild after code or migration changes. The entrypoint runs `bin/rails db:prepare` on start, which migrates the primary and sets up the solid_* databases; it never drops anything.
- The container shares data with `bin/dev`: `./storage` is mounted, and the production primary is the same `storage/development.sqlite3` (WAL mode, two processes are fine), so there is one dataset. Cache, queue and cable use `storage/production_cache.sqlite3`, `production_queue.sqlite3` and `production_cable.sqlite3`. The container runs as root, which rootless Docker maps to the owner, so files stay writable for `bin/dev`. A migration run by the container marks the shared primary's `ar_internal_metadata` environment as `production`, after which dev's protected tasks (`db:drop`, `db:reset`, `db:schema:load`) raise `ProtectedEnvironmentError`; fix it with `bin/rails db:environment:set RAILS_ENV=development`.
- Config comes from `.env` (`env_file`, copied from `.env.example`), including `SECRET_KEY_BASE` and the Strava token encryption keys; there is no credentials file or `master.key`. Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA=1`), including the hourly Garmin and wellness syncs.
- `force_ssl` and `assume_ssl` are off (the LAN speaks plain http). Rails honours `X-Forwarded-Proto` and `X-Forwarded-Host` from any sender, so the Strava OAuth callback is `https://chartlek.rekar.eu/strava/callback` whatever the proxy's address; the tailnet range `100.64.0.0/10` is a trusted proxy (`config/application.rb`) only so that `request.remote_ip` is the real client. Add that URL as the Strava app's callback domain.
- The hourly sync is the only automatic Garmin call.

## Strava API

- Strava only fills the years before Garmin: `Activity::StravaImport` skips Strava runs that start later than 10 minutes before the first Garmin run, and the tasks refuse to run before Garmin is synced. Every Strava-only "run" inside Garmin's history was a hike Garmin recorded as hiking, or a duplicate. Known limit: a phone-only run recorded after Garmin started won't import. The archive (`Archive`) and API (`Api`) sources share `Importer`.
- `.env` needs `STRAVA_CLIENT_ID` and `STRAVA_SECRET`. The tokens shown on strava.com/settings/api only have `read` scope and get 401 on activities, so the app does its own OAuth. `STRAVA_ACCESS_TOKEN` and `STRAVE_REFRESH_TOKEN` in `.env` are unused.
- The connection is stored on `Profile` (`strava_access_token`, `strava_refresh_token`, `strava_token_expires_at`; the tokens use Active Record `encrypts`, with the keys from `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `_DETERMINISTIC_KEY` and `_KEY_DERIVATION_SALT` in `.env`, set in `config/application.rb`. Tests set static keys in `config/environments/test.rb`).
- The nav's Connect Strava button (shown only while disconnected) posts to `StravaConnectionsController#create`, which stores a `state` in the session and redirects to Strava with scope `activity:read_all,profile:read_all`. Strava returns to `GET /strava/callback` (`StravaConnectionsController#show`, redirect URI built from the request; both `http://localhost:3000/strava/callback` and `https://chartlek.rekar.eu/strava/callback` must be allowed by the Strava app). It checks the state, rejects a grant whose `scope` has neither `activity:read` nor `activity:read_all` (nothing stored or queued), exchanges the code, stores tokens and scope and queues a full link. The Connect button's form has `data-turbo=false` so the browser follows the redirect itself (Turbo's fetch would be blocked by CORS).
- `Strava::Client` refreshes when the token expires within 5 minutes and always saves the rotated refresh token. A 401 on activities, or a 400/401 on refresh, clears the stored tokens (`Strava::Client::NotConnected`, the button shows again); other failures raise `Strava::Client::Error` and keep the connection. No retries; 10 s open and read timeouts. The refresh POST is made outside any transaction after reloading the profile; if Strava rejects it but the stored refresh token is no longer the one sent, another process rotated it, so the new token is used and the connection kept. Limits: 100 requests per 15 minutes, 1,000 per day; a full scan at 200 per page is about 15 requests.
- `strava:fetch` uses the stored tokens and aborts with a pointer to the nav button when not connected.
- `activities.strava_id` (nullable, indexed) links a run to its Strava activity and drives the run header's Open in Strava button. Strava-sourced rows get it from `external_id`. `Activity.link_strava_now` (`Activity::StravaLinkJob` through `link_strava_later`) matches each Strava run (`Activity::StravaImport::Api::TYPES`) to the unlinked run whose `started_at` is within 10 minutes, nearest first, and never overwrites a link or reuses a Strava id. Connecting queues a full scan; each successful Garmin sync queues a recent pass, which asks only for activities after the oldest unlinked run of the last 14 days and makes no request when there is none; the same job then runs the gear pass. Strava's own `external_id` is the upload's source file name (`tap-sync-…fit`, a UUID `.tcx`) in pre-Garmin rows, or `garmin_push_N`/`garmin_ping_N`; the matching ignores it.
- Field notes: `start_date` is UTC, and `start_date_local` is local wall-clock time with a `Z` suffix, so parse both as UTC. `average_cadence` is per leg, so double it. `workout_type` 1 is a race. `trainer: true` is a treadmill run. Summaries have no calories (`smashrun:fetch` fills them in).
- Tracks for Strava runs come from Smashrun, not Strava streams. The walk (Strava `214619496`) was deleted, so don't re-import it.

## Smashrun API

Smashrun supplies only the years before Garmin; Garmin-era runs are ignored.

- Login: `POST https://secure.smashrun.com/services/apiauth-jsonservice.asmx/ConnectUserLogin` with JSON `{loginEmail, loginPassword, clientId: "client", scopes: "read_activity", isToken: true}` returns a 12-week token in `results.auth.access_token`. `info.message` reads "An unexpected error occurred on the server" even on success, so check `info.isFailed` and that a token is present.
- Documented API: `https://api.smashrun.com/v1` with `Authorization: Bearer`. 250 requests per hour, no rate-limit headers, so the client spaces calls 15 s apart.
- `GET /my/activities` returns all summaries in one response (`page` and `count` are ignored). Fields: `activityId`, `startDateTimeLocal` (ISO 8601 with offset), `distance` (km), `duration` (s, excluding pauses), `isRace`/`isTreadmill` (0/1), `calories`, HR and cadence average/max/min (cadence is per leg on some runs and both legs on others: `5521783` has 71, per leg, `6528653` has 179, both legs), `elevationGain/Loss`, `startLatitude/Longitude`. `city` is always null.
- `GET /my/activities/{id}` adds series-major `recordingKeys`/`recordingValues` (one array per key, equal lengths): `distance` (km, cumulative), `latitude`, `longitude`, `elevation` (m), `heartRate`, `cadence` (per leg), `clock` (s since start, including pauses), plus `pauseIndexes`, `laps`. Details are stored gzipped as `smashrun-<id>.json.gz`.
- The one Smashrun-only run before Garmin (3 Mar 2015, 8.00 km treadmill) has a distance series ending at 0.18 km, so its distance comes from the summary.
- `bin/rails smashrun:fetch` matches pre-Garmin runs to Strava rows by local wall clock (`local_started_at` against the summary's `startDateTimeLocal` with the offset ignored, within ±10 min, nearest first), because Smashrun's UTC offset is wrong on some runs (`6528653` is 59 min off its Strava twin, which made a UTC match create a duplicate). The Garmin-era cutoff still compares UTC. It fills nil calories, ORs the race flag, creates the Smashrun-only run and attaches the details.

## Open-Meteo

- The run header shows weather through `WeatherHelper#run_weather(run)`: the WMO `code` becomes one condition icon and label (`weather_condition`, a night variant for clear and partly cloudy when `Activity#local_midpoint` is outside sunrise and sunset), then temperature, humidity, wind and rain items, each an inline decorative SVG icon plus the bare value, the words being `sr-only` (`WeatherHelper::ICONS`, layout `WidgetsHelper::META` and `META_ITEM`).
- Hourly values at the run's local midpoint plus daily sunrise and sunset, `timezone=auto`, coordinates rounded to 0.01°. Runs whose midpoint is within `Activity::Weather::ARCHIVE_LAG` (5 days) come from the forecast API (`OpenMeteo::Client#weather(recent: true)`, `start_date`/`end_date` serve the recent past), older runs from the archive; a stored value is never refetched. Nulls from either leave `weather` nil so a later sync retries.

## Landing site

- `site/` is the static landing page for chartlek.com: `index.html`, `styles.css`, the favicon set (`icon.svg`, `favicon.ico`, `apple-touch-icon.png`) and `screenshots/`. Cloudflare Pages serves it with no build command and output directory `site`, so the app is never exposed.
- No JS, no framework, no build step, no analytics, no external fonts or CDNs. Light and dark follow `prefers-color-scheme`.
- `site/screenshots/` is a copy of `docs/screenshots/` (Pages can't reach `docs/`): retake the shots in `docs/screenshots/` and copy them over when the UI changes. The two animations there (`overview-hover.webp`, `run-cursor.webp`, with the stills `overview-hover.png` and `run-cursor.png` for reduced motion) are retaken the same way: recorded frame by frame from the running app with a fake cursor (headless screenshots draw none), mouse moves dispatched along an eased path, and encoded lossless with `ffmpeg -c:v libwebp_anim -lossless 1 -quality 100 -loop 0` (smaller than lossy for flat chart colors). The favicon set is copied from `public/` (the same files the app serves).
- Copy is condensed from the README; update the page when the README's features change.

## Coding style guidelines

See `STYLE.md` for the canonical style rules. Key points for agents:

### Ruby/Rails

- Prefer expanded conditionals over guard clauses for readability.
- Use guard clauses only for early returns at the very top when the main body is non-trivial.
- Do not assign values inside conditionals; assign first, then branch on the result.
- Order methods: class methods, public (with `initialize` first), then `private` methods.
- Order methods vertically by invocation flow (top calls next, etc.).
- Use `!` only when there is a non-`!` counterpart; do not use `!` to signal destructiveness.
- Prefer `return` over `return nil`; use explicit `nil` only when clarity benefits.
- Do not indent method bodies under visibility modifiers; put `private` on its own line.
- Keep controllers thin; call model/domain APIs directly. Services/form objects are allowed but not special.
- Model non-CRUD endpoints as resources, not custom actions on existing resources.
- Prefer job classes that delegate to domain methods; use `_later` and `_now` conventions.
- Write no code comments.

### Imports, modules, and structure

- Class-scoped modules: `app/models/<class>/` and include into the class (`Activity::Performance`).
- Controller mixins: `app/controllers/concerns`.
- App integrations/wrappers: `app/lib` (autoloaded).
- Frontend JS uses Importmap (no Node/Webpack); manage pins in `config/importmap.rb`.

### Formatting and naming

- Ruby: 2-space indent; follow RuboCop `rubocop-rails-omakase` defaults and the house overrides in `.rubocop.yml`.
- Hash and array literals use no inner space: `{a: 1}`, `[1, 2]` (matches `STYLE.md`, unlike omakase default).
- Filenames: Stimulus controllers are kebab-case.
- In JavaScript, prefer one-line early returns whenever they keep the code clear.

### Types and data handling

- Use ActiveRecord validations and types; prefer explicit casting/parsing in models when needed.
- Keep DB access in models; avoid heavy logic in controllers.

### Error handling and control flow

- Avoid exceptions for routine control flow; use validations/return values where possible.
- Use `create!`/`save!` when you want exceptions to bubble; otherwise handle failures explicitly.

### Views and CSS

- Use Tailwind utility classes. Respect existing component patterns.
- Card, page and type classes come from `WidgetsHelper` (`CARD`, `CARD_HEADER`, `CARD_TITLE`, `PAGE_TITLE`, `TILE_*`, `MUTED`, `HINT`, `LEGEND`, `ACCENT`, `LINK`, `PLACEHOLDER`, the `TABLE*` and `CELL` set, `chip`); never redefine them inline. Every page starts with `page_header`, which also sets the `<title>` to "<heading> · Chartlek" (or its `title:` keyword when the heading isn't distinct, as on Runs and the Performance tabs; the run page sets its own from the run's name in `runs/_header`), and every empty page or list uses `empty_state`. Period and month selectors are `button_group "…", nav: true` with `segment href:` (a disabled one is `disabled: true`).
- Controls come from `ControlsHelper` (`button_group` with `segment` for a single choice, `toggle_button`, `action_button` and the `BUTTON` class for `button_to`); never write control classes inline, and never use `<select>` (a choice among options is a button group, `aria-pressed` for buttons and `aria-current` for links).
- `nav_link_to(name, path, match: [path])` marks an item current (accent plus `aria-current="page"`) when `request.path` starts with any prefix in `match`; Overview also matches `goals_path`, and Performance matches `pace_trend_path` and `pr_progress_path`. The two Performance pages render `application/_performance_tabs` (a `button_group nav: true` of links) below `page_header "Performance"`, also in their empty states. `syncs/_status` is re-rendered by `Activity::GarminSync#broadcast_sync_status` (a job) and `SyncsController#create`, so it holds no forms: Sync now sits beside it in the layout.
- Every card uses `CARD` (margins stay at the call site) and every card or nested chart title `CARD_TITLE`. Tiles use one value size (`TILE_VALUE`, the lime `ACCENT` only on headline numbers). `HINT` is the one caption style (type and colour only; each call site sets its own top margin); long explanations go in the ⓘ, and a hint stays only when it tells how to interact with the chart.
- For view edits, run `herb analyze .` and `npx @herb-tools/linter app/views --simple --no-color`.
- Avoid time-dependent computed values inside cached fragments; prefer persisted fields.
