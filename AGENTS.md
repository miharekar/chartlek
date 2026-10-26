# Smashback

This file provides guidance to AI coding agents working with this repository.

## What is Smashback?

Smashback is a local, single-user Rails app. It caches the owner's Garmin Connect running history in SQLite and rebuilds the charts of Smashrun (an abandoned running-stats site) with Tailwind and D3. See `docs/PRD.md` for the full product requirements, phasing and formulas.

# Token efficiency

Respond like smart caveman. Cut all filler, keep technical substance.
- Drop articles (a, an, the), filler (just, really, basically, actually).
- Drop pleasantries (sure, certainly, happy to).
- No hedging. Fragments fine. Short synonyms.
- Technical terms stay exact. Code blocks unchanged.
- Pattern: [thing] [action] [reason]. [next step].

## Development Commands

```bash
bin/setup              # install gems, prepare DB, clear logs/tmp, start bin/dev unless --skip-server
bin/dev                # Rails server on PORT (3000 default), Tailwind watcher and Herb dev server
bin/rails activities:sync    # incremental Garmin sync, foreground
docker compose up -d --build   # build and (re)start the production container on port 9295
docker compose logs -f         # production logs (Puma, Solid Queue, the hourly sync)
bin/rails activities:resync  # full resync, deletes Garmin runs missing upstream
bin/rails activities:download   # fetch and process Garmin originals for runs lacking one (slow: hours; split across `bin/rails runner` processes with `Activity.where("activities.id % 4 = ?", k).download_originals`. Each process throttles itself to 1 request/s, so k processes together exceed the documented 1 request/s: the real backfill with 4 processes averaged about 1.6 requests/s and saw no errors)
bin/rails activities:reprocess  # rebuild tracks and metrics from stored originals
bin/rails smashrun:fetch     # pre-Garmin runs: match, fill calories and races, attach recordings (15 s per request)
bin/rails weather:fetch      # Open-Meteo weather backfill
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

Development URL: http://localhost:3000

## Architecture Overview

- Data lives in SQLite (`storage/`).
- `Activity` is one run, keyed by `(source, external_id)` with `source` `garmin`, `strava` or `smashrun` (only the one Smashrun-only run before Garmin; it has no `garmin_url` or `strava_url`). Class-scoped concerns fill it in: `Activity::GarminSync`, `Activity::StravaImport`, `Activity::StravaLink`, `Activity::SmashrunImport`, `Activity::TrackProcessing`, `Activity::Weather`, `Activity::Browsing`, `Activity::Performance` (VDOT).
- `has_one_attached :original` (Active Storage, local disk): the Garmin ZIP as downloaded, or the gzipped Smashrun detail `smashrun-<id>.json.gz`. `process_original` parses it (`Track::Fit`, `Track::Tcx`, `Track::Smashrun`) into the `tracks` table (columnar JSON `t, d, lat, lng, alt, hr, cad`, at most 2,000 points) and the `splits`, `pace_profile`, `pace_variability` columns. `weather` (JSON) comes from Open-Meteo.
- `Notables.for(activity, runs)` is computed on the fly (needs `weather` loaded; no column). `Food.for(calories)` picks the food equivalent.
- Sync downloads every run it pages through that has no original, processes a run that has an original but no track (so a failed download or parse is retried by the next sync), and reprocesses a run whose `started_at`, `timer_s` or `distance_m` changed (picks up trims; other summary changes don't matter to `process_original`). It refreshes `Profile#sync_started_at` after each run (`Profile#sync_progress`), so a long sync keeps counting as running past `SYNC_STALE_AFTER` and a second Sync now or the hourly run doesn't start a parallel one. Syncs start from the Sync now button (`Activity.sync_later`) and, in production, from the `garmin_sync` task in `config/recurring.yml` (every hour, `Activity::SyncJob`); opening a page no longer syncs. `bin/dev` only syncs on Sync now. It fetches weather for runs 6–60 days old that lack it (the archive lags about 5 days). A failure for one run is logged and skipped.
- FIT parsing uses the owner's fork `gem "fit4ruby", github: "miharekar/fit4ruby"`. `fit_kit` 0.4.0 doesn't build on Ruby 4.0.9 (rb-sys and magnus too old). The fork prefixes its BinData struct field names, so it works with bindata 2.4.10 and newer (CVE-2021-32823); bindata 2.3.1 made `type` a reserved name. `config/initializers/fit4ruby.rb` quiets its logger and no-ops `Fit4Ruby::Activity#check`, fit4ruby's whole post-read validation. It rejected every 2024+ file ("lap_index must be 1, not 0" from the heart-rate zones) and at least one older file ("message_index must be 1, not 0" from `Lap#check`), and nothing our parser uses depends on it for running files. Parsing is slow: 2–8 s per file, about 2,000 records/s.
- Tracks:
  - FIT recordings are clipped because originals are untrimmed: records before `started_at` (−2 s) are dropped and the rest rebased, then records whose timer time exceeds `timer_s` (+2 s) are dropped. A clip to `started_at + elapsed_s` was tried first, but on runs with long pauses Garmin's `elapsed_s` can be shorter than the file's wall-clock span, and it cut real data off the end (5 runs 4–9% short). Now every FIT track is within 1% of its summary's distance and timer; the trimmed run still comes out at 2,461 m.
  - TCX isn't clipped: `Track::Tcx` keeps no per-row timestamps, and `Track::Recording#clip` only clips rows that have `:at`. `Track::Tcx` removes pauses per lap instead: the lap's excess (the time the lap adds to `t`, namely its own gaps plus the gap into its first trackpoint unless that is over 10 s, minus `TotalTimeSeconds`) is taken out of stall gaps, largest first. Stall gaps are over 10 s with distance advancing under 0.5 m/s; gaps where distance keeps advancing are kept, as in the sparse treadmill files. Garmin's `timer_s` for these imports equals the sum of the laps' `TotalTimeSeconds`. On the 64 real TCX runs, 57 end within 0.5% of `timer_s`. Known outliers: `1757715300` (−5.4%, its last lap's samples stop 80 s before the lap total) and `1757716207` (−11.6%, a sparse treadmill file whose first sample comes 328 s after the lap start).
  - If the distance series is missing or more than 10% off `distance_m`, `d` is rebuilt at constant pace, and `splits`, `pace_profile` and `pace_variability` are nil. The run page omits the speed chart for those runs (it renders only when `splits` is present), because identical bars mean nothing.
  - Zero cadence and zero heart rate are missing values for every format (`Track::Recording` turns them into nil): recordings carry cadence 0 while stopped. In the 18 sampled FIT and TCX runs that removed 1,741 zero-cadence points (0 zero heart rate), so the cadence range, chart axis and split averages reflect running only.
  - Smashrun marks samples without a GPS fix with `latitude` = `longitude` = −1.0 and keeps the other series at those samples (real elevation, heart rate). `Track::Smashrun` turns the pair into nil lat/lng. 80 of the 352 details held 1,588 such points, which left 68 stored tracks with route lines shooting out to (−1, −1). No 0/0 or out-of-range markers exist.
  - Smashrun `clock` includes stopped time, and many recordings have no `pauseIndexes` for it. After the distance is settled, `Track::Recording#without_stops(timer_s)` removes the excess of `t` over the row's `timer_s` from stopped intervals (distance advancing under 0.5 m/s), largest first and never more than the excess; final `d` is unchanged. It applies to every non-Garmin row except rebuilt distances, and leaves tracks shorter than `timer_s` alone. `timer_s` is the budget, not the detail's own `duration`: in the 63 runs where they differ by over 2%, the speed-based moving time was closer to `timer_s` in 54 and to `duration` in 9, and the run page's Time tile shows `timer_s`. Across the 352 recorded details, tracks within 2% of `timer_s` went from 269 to 332, tracks over 2% past it from 83 to 20, and tracks over 15% past it from 31 to 1 (worst +86% to +46%); `pace_variability` p95 went from 45.0 to 29.7. The remaining overruns have too little stopped time to remove.
  - Per-split gain and loss are the sums of the `Track::Elevation` 100 m bins (1 m hysteresis carried across bin and km boundaries), so the splits and the per-km elevation bars agree; a split with no known bins has nil gain and loss. Across the 2,508 Garmin runs with a summary, recorded gain and loss total 369,579 m and 367,461 m against Garmin's 363,055 m and 356,639 m (+1.8% and +3.0%; before the threshold carried across km boundaries it was +0.8% and +1.8%, and an earlier 18-run sample gave 3,267 m against 3,274 and 3,431 m against 3,422). Single runs can be off by tens of metres.
  - `Track#bars(100)` gives the 100 m bars for the speed chart.
  - `tracks.chart_metrics` (nullable JSON) is set by `process_original` from the full-resolution recording, before the 2,000-point downsampling: `speed_windows` (metres in each complete 10 s window, behind the variability % and its signed-deviation chart) and `elevation` (`Track::Elevation`: 100 m bins of gain and loss with the 1 m hysteresis carried across bins; the km view sums them). It is nil when the distance is rebuilt, and `elevation` is nil without altitude.
  - The 2017 iSmoothRun treadmill TCX imports have sparse trackpoints and inconsistent Garmin summaries (for example `1757716207`: track `t` 2,501 s against `timer_s` 2,830).
  - Two Garmin runs have rebuilt distances, so their `splits`, `pace_profile` and `pace_variability` are nil: `3843370908` (its summary was edited on Garmin to 3,000 m more than the file holds) and `8547425833` (its records end at 10,998 m, while its session and summary say 17,202 m).
  - Two pre-Garmin Smashrun details (Smashrun `6093331` and `5850866`) have null `recordingKeys` and `recordingValues`. They raise `Track::Error: Smashrun activity has no recording`, so those two Strava runs have no track.
- `Profile` is a singleton (`Profile.instance`) holding Garmin profile settings and sync state (`synced_at`, `sync_started_at`, `sync_error`).
- `started_at` is true UTC. `local_started_at` is the run's local wall-clock time stored as-is. `config.time_zone` stays at the default (UTC) so `local_started_at` is never shifted; use it for all day bucketing (streaks, weekdays, AM/PM, calendars).
- Integration wrappers live in `app/lib` (autoloaded): `Garmin::Client`, `Strava::Client`, `Smashrun::Client`, `OpenMeteo::Client`.
- Frontend is Importmap + Stimulus + D3 + Mapbox GL JS with no Node build. Pins live in `config/importmap.rb`; d3 and Mapbox GL JS are vendored in `vendor/javascript`.
- Theme is Tailwind with zinc neutrals and a lime accent. The theme is System, Light or Dark (the nav's switch, `PATCH /theme` through `ThemesController`, which stores a permanent `theme` cookie and redirects back with a full page load). The layout renders it as `<html data-theme="system|light|dark">`, so there is no flash and no JS before paint. System follows `prefers-color-scheme`. Tailwind's `dark:` variant is a `@custom-variant` on that attribute (dark, or system under the dark media query), and `color-scheme` follows it for native controls. Chart colors come from CSS variables in `app/assets/tailwind/application.css` that switch with the same rule, so D3 code uses them directly (`fill: var(--chart-accent)`) and needs no JS for theme changes (do not use `light-dark()` for them: `getComputedStyle` returns it unresolved, and the map reads these values):
  - `--chart-accent`: main series color (runs, bars, lines).
  - `--chart-accent-highlight`: brighter accent for emphasis and hover.
  - `--chart-accent-low`: dim accent for fills and low-intensity cells.
  - `--chart-highlight`: amber for highlighted points (top runs, latest run, predictions).
  - `--chart-muted`: background dots and de-emphasized marks.
  - `--chart-grid`: grid lines.
  - `--chart-axis`: axis ticks and text.
- Pages: `/overview[/:year[/:month]]`, `/runs`, `/runs/:id`, `/pace_trend`, `/pr_progress`. Routes and the layout are shared seams; page bodies are replaced per feature.
- Every chart click opens the run page in the same tab (no more external links from charts). Pages call `turbo_exempts_page_from_cache`, because charts draw on `connect`.
- Every map in Smashback (the run map now, the Phase 3 Pro Map later) is Mapbox GL JS, never Leaflet or another map library. It is the single-file UMD build `vendor/javascript/mapbox-gl.js` (the `./esm` export is multi-chunk with relative imports, which Propshaft's digested paths break), pinned with `preload: false` and imported dynamically in the controller (it is about 1.9 MB and every controller is eager-loaded). It sets `window.mapboxgl`. Its CSS is `app/assets/stylesheets/mapbox-gl.css`, which draws the required logo and attribution. Styles are `mapbox://styles/mapbox/light-v11` and `dark-v11`, chosen from the `<html data-theme>` attribute (and `prefers-color-scheme` under System, where an OS change calls `setStyle`); `setStyle` drops sources and layers, so add them again on `style.load`. Paint properties can't read CSS variables, so resolve the `--chart-*` colors with `getComputedStyle` when drawing. Every `Map` sets `performanceMetricsCollection: false`: GL JS 3.33 defaults it to on, and it sends the user agent, screen size and GPU to Mapbox (PRD §11 says no analytics). `Track#route` is `[lng, lat]` pairs. `_map.html.erb` renders `MAPBOX_TOKEN` into the page as a Stimulus value, and skips the whole map section unless the token is a public `pk.` one.
- The dev server binds 0.0.0.0 (`Procfile.dev`) and allows the hosts `framework:3000` and `test.rekar.eu`, behind Tailscale. No auth.

### Charts

- Time convention:
  - `local_started_at` goes to JS as epoch ms (`local_started_at.to_i * 1000`), and dates as `YYYY-MM-DD`.
  - Parse them with `parseTime` from `helpers/time`.
  - Use only UTC d3/Date APIs (`d3.scaleUtc`, `d3.utc*`, `getUTC*`), never local-time ones.
- Chart controllers are Stimulus controllers that get server-rendered JSON through Stimulus values.
- Refreshes after a sync use `turbo_refreshes_with method: :replace`, so chart controllers reconnect and redraw; charts must not rely on morphing.
- Escape interpolated names with `escapeHtml` before passing them to `showTooltip`.
- Pages render an empty state instead of charts when there are no runs.
- Overview charts share a hover selection through `helpers/linked_selection.js`: the scatter registers its `runs` (sorted by `t`, with `km`, `pace`, `hr`, `vdot`, `elev`) as the canonical run list, each chart `publish`es `{runs: Set of run indexes, span: [from, to) | null, source}` on hover (and `clearSelection`s on leave and `disconnect`), and the others `subscribe` and only restyle their highlight layer; `publish` batches to one `requestAnimationFrame`. Heatmap cells carry `from` (UTC ms) and the payload a `step` in days; streak rows carry `data-from` and `data-to`. The pure rules (`quadrant`, `periodsAbove`, `bucketShares`, `selectionMean`, …) are in the same file and tested with `node --test`.
- Predictions use the Ruby `Vdot.time_table` plus `predictTime` from `helpers/predictions`.

## Privacy

- Never print or log the Garmin key (`GARMIN_API_TOKEN`), the Strava secret (`STRAVA_SECRET`), the Strava access and refresh tokens (stored encrypted on `profiles`), the Active Record encryption keys in `config/credentials.yml.enc`, the Smashrun credentials (`SMASHRUN_USERNAME`, `SMASHRUN_PASSWORD`) or any access token, including the Smashrun token.
- Test fixtures must be synthetic: no real coordinates, activity names, IDs or health data from the owner's account. Never copy a downloaded original into `test/`.
- `MAPBOX_TOKEN` is a public (`pk.`) token that is rendered into run pages because the browser needs it for tiles. Agents must still never print or log it, and a secret (`sk.`) token must never be used.
- `.env` and `storage/` stay git-ignored.
- `storage/dumps/` holds raw Garmin, Strava and Smashrun API dumps, smashrun.com page captures, audit reports and dev DB backups from Phases 1–2. It is the owner's personal data: never copy it into `test/`, never print it.

## Garmin Personal API

Verified against the real API (Oct 2026):

- Base URL `https://personal.connectapi.garmin.com`. `POST /personalapitoken-service/personal-api/personal-api-key/token` with `Authorization: ApiKey <key>` returns the bearer JWT as a `text/plain` body (not JSON). The JWT has `exp` and `iat` 24 h apart. Data requests use `Authorization: Bearer <jwt>`.
- Activity search: `activityType=running&start&limit`, newest first. `limit=100` works; `limit=250` returns HTTP 500, so use 100. The history (~2,500 runs) takes ~26 pages.
- `activityType=running` also returns `trail_running` (parent type id differs from `running`). `treadmill_running` is seen (4 runs, retyped on Garmin); they sync with `indoor: true` (`INDOOR_TYPES`). No `indoor_running` or `virtual_run` activities were seen, so those two are unverified against real data.
- Unfiltered pages mix in cycling, swimming and hiking, so keep the filter.
- Field notes:
  - `startTimeGMT` and `startTimeLocal` are `"YYYY-MM-DD HH:MM:SS"` strings without zone. Parse both as UTC.
  - `averageHR`, `maxHR` and `calories` are floats. Cadence fields are `averageRunningCadenceInStepsPerMinute` and `maxRunningCadenceInStepsPerMinute`.
  - `eventType.typeKey` is `race` or `uncategorized`.
  - `vO2MaxValue`, `locationName` and `fastestSplit_*` are sometimes missing or nil.
  - A few "runs" have distance under 100 m; sync skips them.
  - Summaries carry `splitSummaries` and `hrTimeInZone_*` but no time series.
- Originals: `GET /download-service/files/activity/{id}` (same bearer auth, through `Garmin::Client#authorized_response`) returns a ZIP holding one file: `<id>_ACTIVITY.fit` for watch runs (0.2–1.2 MB), or `<id>_UNKNOWN.tcx` for the 2017 bulk imports (about 2 MB, 130 KB zipped).
- Originals are untrimmed: Garmin applies trims only to the summary (a run with a 2.46 km summary still holds 4.0 km in its file). Clip FIT records to `[started_at, timer_s of recording time]` (see Tracks above), not to `elapsed_s`.
- Rate limits: no rate-limit or `Retry-After` headers in any response. A full backfill at 1 request/s (28 requests) produced no 429s and no errors.
- Garmin Connect activity URL `https://connect.garmin.com/app/activity/:id` is verified: the owner uses that link and it works.

## Deploy

- The app runs as a container, served at https://run.rekar.eu from this machine: `docker compose up -d --build` builds the image (stock Rails 8.1 Dockerfile on `ruby:4.0.9-slim`, Puma on 3000 without Thruster, assets precompiled) and starts it on port 9295. Caddy on the Pi terminates TLS and proxies to it over Tailscale; on the LAN use `http://<host>:9295`. `docker compose logs -f` shows the logs (STDOUT), and `docker compose ps` the state.
- Rebuild after code or migration changes. The entrypoint runs `bin/rails db:prepare` on start, which migrates the primary and sets up the solid_* databases; it never drops anything.
- The container shares the data with `bin/dev`: `./storage` is mounted, and the production primary database is the same `storage/development.sqlite3` (SQLite in WAL mode, two processes are fine), so there is one dataset. Cache, queue and cable use `storage/production_cache.sqlite3`, `production_queue.sqlite3` and `production_cable.sqlite3`. The container runs as root, which rootless Docker maps to the owner, so the files stay writable for `bin/dev`. A migration run by the container marks the shared primary's `ar_internal_metadata` environment as `production`, after which dev's protected tasks (`db:drop`, `db:reset`, `db:schema:load`) raise `ProtectedEnvironmentError`; fix it with `bin/rails db:environment:set RAILS_ENV=development`.
- Config comes from `.env` (`env_file`) and the read-only `config/master.key` mount (credentials and the Strava token encryption keys). Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA=1`), including the hourly Garmin sync.
- `force_ssl` and `assume_ssl` are off (the LAN speaks plain http). Rails honours `X-Forwarded-Proto` and `X-Forwarded-Host` from any sender, so the Strava OAuth callback is `https://run.rekar.eu/strava/callback` whatever the proxy's address; the tailnet range `100.64.0.0/10` is added to the trusted proxies (`config/application.rb`) only so that `request.remote_ip` is the real client behind Caddy. Add `https://run.rekar.eu/strava/callback` as the Strava app's callback domain.
- The first Strava connect and link happen against the live API after deploy, and the hourly sync is the only automatic Garmin call.

## Strava API

- Strava only fills the years before Garmin: `Activity::StravaImport` skips Strava runs that start later than 10 minutes before the first Garmin run, and the tasks refuse to run before Garmin is synced. Every Strava-only "run" inside Garmin's history was a hike Garmin recorded as hiking (Strava lists it as a run) or a duplicate. Known limit: a phone-only run recorded after Garmin started won't import. The archive (`Archive`) and API (`Api`) sources share `Importer`.
- `.env` needs `STRAVA_CLIENT_ID` and `STRAVA_SECRET`. The tokens shown on strava.com/settings/api only have `read` scope and get 401 (`activity:read_permission` missing) on activities, so the app does its own OAuth.
- The connection is stored on `Profile` (`strava_access_token`, `strava_refresh_token`, `strava_token_expires_at`; the two tokens use Active Record `encrypts`, with the keys in `config/credentials.yml.enc` under `active_record_encryption`, opened by the git-ignored `config/master.key`; the container mounts `config/master.key` read-only, and setting `RAILS_MASTER_KEY` works too. Tests set static keys in `config/environments/test.rb`). The nav's Connect Strava button (shown only while disconnected) posts to `StravaConnectionsController#create`, which stores a `state` in the session and redirects to Strava with scope `activity:read_all`. Strava returns to `GET /strava/callback` (`StravaConnectionsController#show`, redirect URI built from the request, so `http://localhost:3000/strava/callback` locally and `https://run.rekar.eu/strava/callback` in production; both need to be allowed by the Strava app), which checks the state, rejects a grant whose `scope` has neither `activity:read` nor `activity:read_all` (nothing stored or queued), exchanges the code, stores the tokens and queues a full link. The Connect button's form has `data-turbo=false` so the browser follows the redirect to Strava itself (Turbo's fetch would be blocked by CORS).
- `Strava::Client` refreshes when the token expires within 5 minutes and always saves the rotated refresh token. A 401 on activities, or a 400/401 on refresh, clears the stored tokens (`Strava::Client::NotConnected`, the button shows again); other failures raise `Strava::Client::Error` and keep the connection. There are no retries, and requests use 10 s open and read timeouts. The refresh POST is made outside any transaction after reloading the profile; if Strava rejects it but the stored refresh token is no longer the one sent, another process rotated it, so the new token is used and the connection kept. Limits: 100 requests per 15 minutes and 1,000 per day; a full scan at 200 per page is about 15 requests.
- `strava:fetch` uses the stored tokens and aborts with a pointer to the nav button when not connected. `STRAVA_ACCESS_TOKEN` and `STRAVE_REFRESH_TOKEN` in `.env` are unused.
- `activities.strava_id` (nullable, indexed) links a run to its Strava activity and drives the run header's Open in Strava button. Strava-sourced rows get it from `external_id`. `Activity.link_strava_now` (`Activity::StravaLinkJob` through `link_strava_later`) matches each Strava run (`Activity::StravaImport::Api::TYPES`) to the unlinked run whose `started_at` is within 10 minutes, nearest first, and never overwrites a link or reuses a Strava id. Connecting queues a full scan; each successful Garmin sync queues a recent pass, which asks Strava only for activities after the oldest unlinked run of the last 14 days and makes no request when there is none. Strava's own `external_id` is the upload's source file name (`tap-sync-…fit`, a UUID `.tcx`) in the pre-Garmin rows; Garmin-pushed activities may carry `garmin_push_N`/`garmin_ping_N`, which the matching does not use.
- Field notes: `start_date` is UTC, and `start_date_local` is local wall-clock time with a `Z` suffix, so parse both as UTC. `average_cadence` is per leg, so double it. `workout_type` 1 is a race. `trainer: true` is a treadmill run. Summaries have no calories (`smashrun:fetch` fills them in).
- Tracks for Strava runs come from Smashrun, not Strava streams. The walk (Strava `214619496`) was deleted, so don't re-import it.

## Smashrun API

Verified against the real account (Oct 2026). Smashrun supplies only the years before Garmin; Garmin-era runs are ignored.

- Login: `POST https://secure.smashrun.com/services/apiauth-jsonservice.asmx/ConnectUserLogin` with JSON `{loginEmail, loginPassword, clientId: "client", scopes: "read_activity", isToken: true}` returns a 12-week token in `results.auth.access_token`. `info.message` reads "An unexpected error occurred on the server" even on success, so check `info.isFailed` and that a token is present.
- Documented API: `https://api.smashrun.com/v1` with `Authorization: Bearer`. 250 requests per hour, no rate-limit headers, so the client spaces calls 15 s apart.
- `GET /my/activities` returns all summaries in one response (`page` and `count` are ignored). Fields: `activityId`, `startDateTimeLocal` (ISO 8601 with offset), `distance` (km), `duration` (s, excluding pauses), `isRace`/`isTreadmill` (0/1), `calories`, HR and cadence average/max/min (cadence is per leg on some runs and both legs on others: `5521783` has `cadenceAverage` 71, per leg, and `6528653` has 179, both legs), `elevationGain/Loss`, `startLatitude/Longitude`. `city` is always null.
- `GET /my/activities/{id}` adds series-major `recordingKeys`/`recordingValues` (one array per key, equal lengths): `distance` (km, cumulative), `latitude`, `longitude`, `elevation` (m), `heartRate`, `cadence` (per leg), `clock` (s since start, including pauses), plus `pauseIndexes`, `laps`. Details are stored gzipped as `smashrun-<id>.json.gz`.
- The one Smashrun-only run before Garmin (3 Mar 2015, 8.00 km treadmill) has a distance series ending at 0.18 km, so its distance comes from the summary.
- `bin/rails smashrun:fetch` matches pre-Garmin runs to Strava rows by local wall clock (`local_started_at` against the summary's `startDateTimeLocal` with the offset ignored, within ±10 min, nearest first), because Smashrun's UTC offset is wrong on some runs (`6528653` is 59 min off its Strava twin, which made a UTC match create a duplicate). The Garmin-era cutoff still compares UTC. It fills nil calories, ORs the race flag, creates the Smashrun-only run and attaches the details.

## Open-Meteo

- Archive API, hourly values at the run's local midpoint plus daily sunrise and sunset, `timezone=auto`, coordinates rounded to 0.01°. The archive lags about 5 days: nulls leave `weather` nil so a later sync retries.

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
- Rails naming conventions apply for classes, modules, and files.
- In JavaScript, prefer one-line early returns whenever they keep the code clear.

### Types and data handling

- Use ActiveRecord validations and types; prefer explicit casting/parsing in models when needed.
- Keep DB access in models; avoid heavy logic in controllers.

### Error handling and control flow

- Avoid exceptions for routine control flow; use validations/return values where possible.
- Use `create!`/`save!` when you want exceptions to bubble; otherwise handle failures explicitly.

### Views and CSS

- Use Tailwind utility classes. Respect existing component patterns.
- For view edits, run `herb analyze .` and `npx @herb-tools/linter app/views --simple --no-color`.
- Avoid time-dependent computed values inside cached fragments; prefer persisted fields.
