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
bin/dev                # Rails server on PORT (3000 default) and Tailwind watcher
bin/rails activities:sync    # incremental Garmin sync, foreground
bin/rails activities:resync  # full resync, deletes Garmin runs missing upstream
bin/rails strava:fetch       # gap fill from the Strava API (browser authorization)
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
- `Activity` is one run, keyed by `(source, external_id)` with `source` either `garmin` or `strava`. Class-scoped concerns fill it in: `Activity::GarminSync`, `Activity::StravaImport`, `Activity::Performance` (SPI/VDOT).
- `Profile` is a singleton (`Profile.instance`) holding Garmin profile settings and sync state (`synced_at`, `sync_started_at`, `sync_error`).
- `started_at` is true UTC. `local_started_at` is the run's local wall-clock time stored as-is. `config.time_zone` stays at the default (UTC) so `local_started_at` is never shifted; use it for all day bucketing (streaks, weekdays, AM/PM, calendars).
- Integration wrappers live in `app/lib` (autoloaded), for example `Garmin::Client`.
- Frontend is Importmap + Stimulus + D3 with no Node build. Pins live in `config/importmap.rb`; d3 is vendored in `vendor/javascript`.
- Theme is Tailwind with zinc neutrals and a lime accent. Light and dark follow the system via `prefers-color-scheme`. Chart colors come from CSS variables in `app/assets/tailwind/application.css` that switch automatically, so D3 code uses them directly (`fill: var(--chart-accent)`) and needs no JS for theme changes:
  - `--chart-accent`: main series color (runs, bars, lines).
  - `--chart-accent-highlight`: brighter accent for emphasis and hover.
  - `--chart-accent-low`: dim accent for fills and low-intensity cells.
  - `--chart-highlight`: amber for highlighted points (top runs, latest run, predictions).
  - `--chart-muted`: background dots and de-emphasized marks.
  - `--chart-grid`: grid lines.
  - `--chart-axis`: axis ticks and text.
- Pages: `/overview[/:year[/:month]]`, `/pace_trend`, `/pr_progress`. Routes and the layout are shared seams; page bodies are replaced per feature.

### Charts

- Time convention:
  - `local_started_at` goes to JS as epoch ms (`local_started_at.to_i * 1000`), and dates as `YYYY-MM-DD`.
  - Parse them with `parseTime` from `helpers/time`.
  - Use only UTC d3/Date APIs (`d3.scaleUtc`, `d3.utc*`, `getUTC*`), never local-time ones.
- Chart controllers are Stimulus controllers that get server-rendered JSON through Stimulus values.
- Refreshes after a sync use `turbo_refreshes_with method: :replace`, so chart controllers reconnect and redraw; charts must not rely on morphing.
- Escape interpolated names with `escapeHtml` before passing them to `showTooltip`.
- Pages render an empty state instead of charts when there are no runs.
- Predictions use the Ruby `Spi.time_table` / `Vdot.time_table` plus `predictTime` from `helpers/predictions`.

## Privacy

- Never print or log the Garmin key (`GARMIN_API_TOKEN`), the Strava secret (`STRAVA_SECRET`) or any access token.
- Test fixtures must be synthetic: no real coordinates, activity names, IDs or health data from the owner's account.
- `.env` and `storage/` stay git-ignored.

## Garmin Personal API

Verified against the real API (Oct 2026):

- Base URL `https://personal.connectapi.garmin.com`. `POST /personalapitoken-service/personal-api/personal-api-key/token` with `Authorization: ApiKey <key>` returns the bearer JWT as a `text/plain` body (not JSON). The JWT has `exp` and `iat` 24 h apart. Data requests use `Authorization: Bearer <jwt>`.
- Activity search: `activityType=running&start&limit`, newest first. `limit=100` works; `limit=250` returns HTTP 500, so use 100. The history (~2,500 runs) takes ~26 pages.
- `activityType=running` also returns `trail_running` (parent type id differs from `running`). No `treadmill_running`, `indoor_running` or `virtual_run` activities were seen in this account, so the indoor flag is unverified against real data.
- Unfiltered pages mix in cycling, swimming and hiking, so keep the filter.
- Field notes:
  - `startTimeGMT` and `startTimeLocal` are `"YYYY-MM-DD HH:MM:SS"` strings without zone. Parse both as UTC.
  - `averageHR`, `maxHR` and `calories` are floats. Cadence fields are `averageRunningCadenceInStepsPerMinute` and `maxRunningCadenceInStepsPerMinute`.
  - `eventType.typeKey` is `race` or `uncategorized`.
  - `vO2MaxValue`, `locationName` and `fastestSplit_*` are sometimes missing or nil.
  - A few "runs" have distance under 100 m; sync skips them.
  - Summaries carry `splitSummaries` and `hrTimeInZone_*` but no time series.
- Rate limits: no rate-limit or `Retry-After` headers in any response. A full backfill at 1 request/s (28 requests) produced no 429s and no errors.
- Garmin Connect activity URL `https://connect.garmin.com/app/activity/:id` is an assumption; it can't be checked without logging in.

## Strava API

- Strava only fills the years before Garmin: `Activity::StravaImport` skips Strava runs that start later than 10 minutes before the first Garmin run, and the tasks refuse to run before Garmin is synced. Every Strava-only "run" inside Garmin's history was a hike Garmin recorded as hiking (Strava lists it as a run) or a duplicate. Known limit: a phone-only run recorded after Garmin started won't import. The archive (`Archive`) and API (`Api`) sources share `Importer`.
- `.env` needs `STRAVA_CLIENT_ID` and `STRAVA_SECRET`. The tokens shown on strava.com/settings/api only have `read` scope and get 401 (`activity:read_permission` missing) on activities.
- `strava:fetch` authorizes `activity:read_all` in the browser: Strava redirects to a one-shot listener on `http://127.0.0.1:8137/strava/callback` (Strava allows localhost and 127.0.0.1 redirects). If the browser runs on another machine, its redirect page fails to load; `curl` that address-bar URL on this machine to hand the code to the listener. Tokens live only in the task's memory.
- Field notes: `start_date` is UTC, and `start_date_local` is local wall-clock time with a `Z` suffix, so parse both as UTC. `average_cadence` is per leg, so double it. `workout_type` 1 is a race. `trainer: true` is a treadmill run. Summaries have no calories.

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
- Avoid time-dependent computed values inside cached fragments; prefer persisted fields.
