# Smashback: Product Requirements Document

- **Status:** Draft v2
- **Date:** 2026-10-25
- **Owner:** Miha Rekar
- **Repo:** `~/Projects/Personal/smashback`

## 1. Summary

Smashback is a local, single-user Rails app. It caches your Garmin Connect running history in SQLite and rebuilds Smashrun's charts, free and Pro, with a modern Tailwind UI and charts built directly on D3.

Why: Smashrun (smashrun.com/miharekar) is effectively abandonware, but its charts are still the best way to look at a long running history. The ask in [dreeveapp/dreeve#2880](https://github.com/dreeveapp/dreeve/issues/2880) was turned down because most of these charts are too runner-specific for a general-purpose app. Smashback is only about running, so it can include all of them.

## 2. Goals and non-goals

### Goals

- **G1:** Rebuild every Smashrun overview chart and the Pro analytics: Pace Trends, PR Progress, Training Bands, Progress Towards Goal, Pro Map, and the run page.
- **G2:** Use the Garmin Connect Personal API as the primary source and cache everything in SQLite. The UI never waits on Garmin.
- **G3:** Fill the years before Garmin from the Strava API; take their tracks, and any Smashrun-only runs, from the Smashrun API.
- **G4:** Make the UI fast and modern: Tailwind, light and dark theme following the system, and D3 charts as Stimulus controllers.
- **G5:** Show Garmin wellness trends (resting HR, VO2max, HRV, weight, sleep, Body Battery/stress) next to running performance.

### Non-goals

These are explicitly out of scope:

- Badges.
- Anything social: friends, ranks, rarity %, invites, sharing.
- Weekly email report.
- Cooper test view.
- Local run tags, notes or edits.
- Running power (Stryd or native).
- Multi-user support, authentication, and production deployment.
- Imperial units, including mile benchmarks.
- Writing anything back to Garmin.
- A mobile app.

## 3. Decisions log

| Topic | Decision |
|---|---|
| Users | Just you. Single user, no accounts. |
| Hosting | Your machine, reachable over Tailscale (`bin/dev` binds 0.0.0.0; hosts `framework:3000`, `test.rekar.eu`). No auth. |
| Garmin access | [Garmin Connect Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api/). The key is in `.env` as `GARMIN_API_TOKEN`. |
| History gaps | Strava API (archive as fallback) for runs before Garmin, plus Smashrun for their tracks and the one Smashrun-only run. |
| FIT parser | `fit4ruby` from your fork `miharekar/fit4ruby`. `fit_kit` doesn't build on Ruby 4.0.9. The fork prefixes its BinData struct field names, so it works with bindata 2.4.10 and newer (CVE-2021-32823); bindata 2.3.1 made `type` a reserved name. An initializer quiets its logger and no-ops `Fit4Ruby::Activity#check`, its post-read validation, which rejects every 2024+ file and at least one older one. About 2,000 records/s. |
| Map | Mapbox GL JS for every map (run map now, Pro Map in Phase 3), loaded through Importmap (vendored UMD build, CSS vendored), with the `mapbox/light-v11` and `mapbox/dark-v11` styles following the system theme. The public `MAPBOX_TOKEN` from `.env` is rendered into the page. |
| Activity types | All running subtypes: road, trail, track, treadmill, indoor, virtual, ultra. Treadmill, indoor and virtual runs are flagged so they can be filtered out. |
| v1 scope | Overview dashboard, Pace Trends, PR Progress (with predictions and Magic PRs). |
| Eventually | Everything except badges: run page, Pro Map, Training Bands, Goals, wellness. |
| Extras | Notables, food equivalents, Garmin wellness data (resting HR, VO2max, HRV, weight, sleep, Body Battery/stress). |
| Performance index | Both. A Purdy Points–based SPI (0–1000, like Smashrun) is the main number, with Jack Daniels' VDOT shown alongside. |
| Units | Metric only: km, min/km, m, °C, 24h clock, weeks start Monday. |
| Look | Light and dark, following the system. |
| Name | `smashback` |
| Stack | `rails new` (Rails 8.1.4, Ruby 4.0.9 via mise), SQLite, Tailwind, Importmap, Hotwire, D3. Follows Visualizer's `STYLE.md` conventions. |

## 4. Phasing

| Phase | Ships | Exit criteria |
|---|---|---|
| **0: Foundation** | App skeleton, Garmin client, activity sync from summaries, Strava archive import, nav and sync status | `Sync now` imports all Garmin runs. The Strava task imports only gap runs. Tests pass. |
| **1: v1** | Overview (§5.2), Pace Trends (§5.3), PR Progress (§5.4) | All widgets per spec. Golden values (§12) within tolerance. Light and dark both verified. |
| **2: Runs** | Original download and parsing (FIT, TCX, Smashrun recordings), runs list, run page (§5.5), weather, notables, food equivalents, PR sparklines, Analyze Run View | Every run has a parsed track (Garmin original or Smashrun recording). Run page complete. |
| **3: Pro analytics** | Pro Map (§5.6), Training Bands (§5.7), Progress Towards Goal (§5.8) | Per spec. |
| **4: Wellness** | Wellness page and overlays (§5.9) | Per spec. Phase 4 doesn't depend on Phases 2–3 and can be pulled earlier. |

**Phase 1 needs only activity summaries.** The Personal API's activity search returns distance, duration, HR, elevation, local start time, type and event type. That's enough for everything in Phase 1 except the PR sparklines, which move to Phase 2. Phase 1 therefore doesn't download or parse originals.

## 5. Feature specs

### 5.1 Global

- **Nav:** Overview, Runs, Pace Trends, PR Progress. Later phases add Training Bands, Goals and Wellness.
- **Sync status in the nav:**
  - Shows "Synced 12 min ago" and a **Sync now** button.
  - Opening the app triggers a sync if the last one was more than 30 min ago.
  - A sync that created, changed or deleted runs, or that changed the error state, refreshes the page with a Turbo `:replace` refresh (`turbo_refreshes_with method: :replace`). Morphing would wipe the D3-drawn SVGs; a full replace makes the chart controllers reconnect and redraw.
  - Any other sync only replaces the nav sync status in place. The status also shows "Syncing…" live when a sync starts, and no page state (modes, selections, brushed windows) is lost.
  - If the Garmin key has expired, a banner explains how to rotate it (§11).
- **Formatting:**
  - Pace: `m:ss /km`.
  - Durations: `h:mm:ss`.
  - Distances: 1 decimal place in km.
  - Dates: `21 Apr 2020`.
  - Numbers use `tabular-nums`.
- **Links:**
  - Phase 1: clicking a run in any chart opened it on Garmin Connect (`connect.garmin.com/app/activity/:id`, verified) or on Strava for gap runs.
  - Phase 2: clicks open the run page in the same tab instead. The run page links out to Garmin or Strava.
- **Chart info:** every chart has an ⓘ popover explaining how to read it, adapted from Smashrun's FAQ.

### 5.2 Overview (Phase 1)

Routes: `/` → `/overview`, `/overview/:year`, `/overview/:year/:month`.

The period selector offers **All time**, a pill for every year (newest first), and month pills for the selected year (months without runs are disabled). The period applies to every widget.

| # | Widget | Spec |
|---|---|---|
| 1 | Kilometers run | Big total with the number in English words underneath, Smashrun-style ("thirty three thousand four hundred sixty four"). Run count. |
| 2 | Most / least often run on | Weekday with the most or least distinct run days; shows days and average km per run day. |
| 3 | Average run length | km |
| 4 | Average days run per week | Distinct run days ÷ weeks in the period. For all time, the period runs from the first run to today. |
| 5 | Time of day | % of runs starting after noon (local time), with a small AM/PM donut. |
| 6 | Average pace | Total timer time ÷ total distance. |
| 7 | Longest run | km and date; links to the run. |
| 8 | Distance per period | Bars: per month (all time), per week (year), per day (month). The metric in the title is switchable: **Distance** / Elevation gained / Avg distance / Avg pace / Avg SPI. Hover shows value and run count. Clicking a bar drills into that period. |
| 9 | Trailing days | Daily rolling sum of distance: 365 days (all-time view), 90 (year), 7 (month). |
| 10 | Runs pace vs distance | Scatter of runs in the period. x = km. y = pace on a speed-linear axis labeled as pace (ticks 4:00, 5:00, 6:00, 7:30, 10:00, 15:00, 30:00). The last run is highlighted and the average is a ring marker. The y metric is switchable: **Pace** / Avg HR / SPI. |
| 11 | Consecutive days run | Longest streak and longest break with dates, plus the current streak or break. |
| 12 | Weekly stats for each year | All-time view: heatmap with years as rows and Monday-start weeks as columns. Weekly km buckets: >1, >20, >40, >50, >60 (ring), >80 (dot). Year and month views show a day calendar colored by daily km instead. |
| 13 | Personal records | Benchmarks: 3 km, 5 km, 10 km, 15 km, 20 km, half marathon, 40 km, marathon, 50 km, 100 km. Only benchmarks with qualifying runs in the period are shown. Each row: date, pace, km/h, time, number of runs in the bucket, and a race tag. Phase 2 adds a pace sparkline per row (20-segment pace profile). |

### 5.3 Pace Trends (Phase 1)

This answers "am I getting faster?" by putting all distances on a common scale (SPI).

**Main chart**

- x = date, y = SPI, with a toggle to show **VDOT** instead.
- Every run is a small muted dot.
- **Top runs** are accent (yellow) dots joined by a faint smoothed line. A run is a top run if it is in the top 3 by SPI within the 30 days ending on its date (see §6).
- A **regression band** shows the least-squares line through the top runs inside the selected window, ±1 SD of the residuals.

**Timeline and window**

- Below the main chart, a timeline of bars shows each run's duration in hours over the whole history.
- A `d3-brush` on the timeline selects the window; the default is the last 12 months. The main chart zooms to the window.
- The header shows:
  - The date range.
  - "Change in SPI: **+0.6/week**", the slope × 7.
  - "Cut **34:28** from your estimated **[Marathon ▾]** finish time". This is the predicted time at the chosen distance (5K, 10K, half, marathon), using the regression SPI at the start of the window versus the end. If the result is negative, it reads "Added".
- The regression and header are recomputed in the browser while dragging, with no server round trip.

**Filters**

Toggle chips:

- Exclude runs with pauses.
- Exclude treadmill/indoor/virtual.
- Races only (Garmin event type `race`).

**Tooltip**

Shows date, name, SPI, VDOT, distance, pace and time. Clicking a run opens its run page, which includes the Analyze Run View: the 90 days of training before that run.

**Later**

Phase 4 adds a secondary-axis overlay toggle for resting HR or VO2max.

### 5.4 PR Progress (Phase 1)

**Main chart**

- x = distance on a log scale. y = pace on a speed-linear axis, faster at the top.
- All runs are shown as muted dots.
- An **all-time frontier** line runs through the benchmark PRs (§6). It marks the boundary between your best and what's left to achieve.

**Timeline brush**

- Below the chart is a timeline of runs per day with a brush.
- Selecting a window draws a second line: the best performance at each benchmark among runs in that window. This compares a period against your all-time bests.
- Dragging the brush scrubs through history, showing how long it has been since you ran or set a PR at each distance.

**"PRs you can beat"**

1. Pick a reference period: last 30, 60 or 90 days.
2. The reference run is the run with the highest SPI in that period. It is shown and can be changed by clicking another run.
3. The chart draws the predicted time at each benchmark at the same SPI.
4. Predictions that beat the all-time PR are highlighted. Tooltips show predicted time, pace, and % improvement over the current PR.

**"Magic PRs"**

1. For each benchmark, the target is the next round time below your current PR.
2. Steps: 1 min for distances ≤ 5 km, 5 min up to the half marathon, 15 min for longer. For example: 5 km 24:23 → 24:00, half 1:37:30 → 1:35:00, marathon 3:20:32 → 3:15:00.
3. The 3 targets with the smallest % gap are shown as pulsing markers, with tooltips like "Sub-3:15 marathon: shave 5:32 (2.8%)".
4. The step table is a constant and easy to tune.

### 5.5 Runs list and run page (Phase 2)

**Runs list (`/runs`, filterable by year and month)**

- Sortable table: date, name, km, time, pace, HR, elevation, SPI, VDOT.
- Race and treadmill tags.

**Run page (`/runs/:id`)**

- **Header:**
  - Local date and time, start–end clock time.
  - Weather: temperature, humidity, wind, from Open-Meteo at the run's midpoint hour.
  - Location name (Garmin only), link to Garmin or Strava (none for Smashrun-only runs), previous/next run.
  - If there were several runs that day, a switcher between them.
- **Tiles:**
  - Distance, elapsed/timer/moving time, average pace and speed.
  - Calories with a food equivalent ("A bunch of bananas… or a kremšnita").
  - Average HR (min–max), average cadence (min–max), elevation gain and loss.
  - SPI and VDOT.
  - **Pace variability** (%), shown as Smashrun's circle glyph.
  - **Nth longest run** and **Nth fastest for a similar distance** (±10%), each with a mini rank chart.
  - **Estimated finish times** for 5K, 10K, half and marathon at this run's SPI.
- **Change in speed over route:**
  - Bars per 100 m, toggleable to per-km splits.
  - Brushing a range shows a summary of the selection: distance, time, pace, HR, cadence.
- **Elevation, HR and cadence charts:** these share the x-axis (distance) and a synced hover.
- **Route map:** a basic Mapbox GL JS route line. The Pro Map comes in Phase 3, also on Mapbox GL JS.
- **Notables** as of the run's date (§6).
- **Fastest runs for this distance:** for the last 90, 180 and 365 days.
- **Analyze Run View (training in the prior 90 days):**
  - A histogram of the 90 days before the run, by distance, pace, HR or SPI (selectable), above a timeline of those runs.
  - Brushing the histogram highlights the matching runs in the timeline.
  - Shows run count, distance, duration, and % of total training for the selection.
- **Overview:** the PR sparklines (§5.2 #13) light up once tracks are parsed.

### 5.6 Pro Map (Phase 3)

- **Route coloring:**
  - The route is split into segments and colored by the selected metric:
    - **Pace:** absolute buckets from walking (dark red) to "super fast" (white), fixed across all runs so that improvement is visible.
    - **HR:** your Garmin HR zones.
    - **Grade:** −10% to +10%.
    - **Cadence:** cadence ranges.
  - Map tiles follow the light/dark theme.
- **Distribution bars** under the map, using Smashrun's click cycle: 1× selects only that bucket, 2× that bucket and above, 3× that bucket and below, 4× resets. The legend shows distance, duration, average pace, HR and cadence for the selection.
- **Fastest segments:** 250 m, 400 m, 1 km, 5 km, 10 km, half, … up to the run's length, each with pace and SPI. Clicking one isolates it on the map and updates the stats.
- **Splits** per km for pace, elevation, HR or cadence, following the current metric. Clicking a split isolates it.
- **Change-in-pace graph** under the map. Hovering another metric's filter overlays that metric on a secondary axis.

### 5.7 Training Bands (Phase 3)

- Each run is precomputed into seconds per pace bucket, HR zone and grade bucket.
- These are shown as a stacked area chart per week across all history:
  - Category toggle: pace, HR or grade.
  - Absolute or % view.
  - Band filters, for example "tempo and faster" or "HR zone 4+".
  - Timeline brush to zoom.

### 5.8 Progress Towards Goal (Phase 3)

**Goals**

- Monthly and yearly distance goals, stored locally with CRUD.
- They also appear as widgets on the Overview, as on Smashrun.

**Chart**

- An accent line shows cumulative distance. A grey line shows the direct path to the goal (goal ÷ days).
- Hovering a past date shows where you were. Hovering a future date shows the required average distance per day from now on.
- When you're behind, a red catch-up line appears. Its intensity is the required daily distance relative to your recent daily average.
- The x-axis has ticks on run days with daily totals; clicking one opens that run.

### 5.9 Wellness (Phase 4)

- **Page `/wellness`:**
  - Resting HR (daily, with a 7-day average).
  - HRV (nightly average with Garmin's baseline band).
  - VO2max: step line from activity summaries, overlaid on the SPI trend.
  - Weight (measurements with a trend line).
  - Sleep (duration and score).
  - Body Battery (daily high/low) and stress (daily average).
- **Shared controls:** a shared date range and the same brush pattern as Pace Trends.
- **Overlays:** resting HR and VO2max can be overlaid on Pace Trends (§5.3).

## 6. Metrics and formulas

All metric math lives in Ruby and is unit-tested. The only JS math is interactive recomputation (regression, brush stats), and it has `node --test` tests.

- **Run eligibility:** an activity counts if its type is a running subtype and its distance is ≥ 0.1 km. Treadmill, indoor and virtual runs are counted but flagged.
- **Time basis:**
  - `timer_s` is Garmin's `duration`, which excludes manual pauses. It drives pace, SPI and PRs.
  - `elapsed_s` and `moving_s` are also stored.
  - A run *has pauses* when `elapsed_s − timer_s ≥ 60`.
- **Local time:** all day bucketing (streaks, weekdays, AM/PM, calendars) uses Garmin's `startTimeLocal`. UTC is stored as well.
- **SPI:**
  - Purdy points P for (distance, `timer_s`), using the 1974 least-squares running curve (J. G. Purdy, "Least squares model for the running curve", *Research Quarterly* 45, 1974; scoring scale from Gardner & Purdy, *Computer generated track scoring tables*, 1970):
    - V(d) = −b₁e^(−r₁d) + b₂e^(−r₂d) + b₃e^(−r₃d) + b₄e^(−r₄d) + b₅e^(−r₅d), the 1970 world-record velocity in m/s at distance d in m.
    - A = 85 / (0.0654 − 0.00258·V), B = 1 − 1035/A, P = A·((d/V)/t − B). A 1970 world record scores 1035.
    - b = 11.15895, 4.304605, 0.5234627, 4.031560, 2.316157; r = 3.796158e−2, 1.646772e−3, 4.107670e−4, 7.068099e−6, 5.220990e−9.
  - Raw P goes negative for easy runs, so it is not clamped. It is rescaled to Smashrun's anchors: SPI = 1 + 999·(P − P_walk)/(1000 − P_walk), clamped to 1..1000, where P_walk = P(5 km, 1 h) is SPI 1 and P = 1000 is SPI 1000.
  - `nil` for runs under 400 m or a time ≤ 0.
  - Golden tests: 1970 world records score near 1035, and 5 km / 10 km / 20 km times track the published 1970 Gardner–Purdy table (a different, table-based model on a 950-point scale, so the tolerance is loose).
- **VDOT** (Daniels–Gilbert):
  - v = m/min, t = minutes.
  - VO2 = −4.60 + 0.182258·v + 0.000104·v²
  - %max = 0.8 + 0.1894393·e^(−0.012778·t) + 0.2989558·e^(−0.1932605·t)
  - VDOT = VO2 / %max
- **Predictions:**
  - Time at distance D for a given SPI comes from inverting the Purdy function in closed form: t = A·T_w / (P + A − 1035), where T_w = d/V(d) and P is the points for that SPI.
  - The VDOT-based equivalent is shown in tooltips.
- **PRs (Smashrun rule):**
  - For benchmark D, qualifying runs have D ≤ distance < D + 1 km.
  - PR time = `timer_s × D / distance` (time interpolated at constant pace).
  - Bucket count = number of qualifying runs.
  - A PR is "official" when the Garmin event type is `race`.
- **Streak and break:**
  - A streak is maximal consecutive local dates with ≥ 1 run.
  - A break is maximal consecutive dates without a run, between the first run and the end of the period.
- **Trailing N days:** for each date, the sum of distance over `[date − N + 1, date]`.
- **Top runs (Pace Trends):** a run is a top run if its SPI ranks ≤ 3 among runs in `[date − 29 days, date]`. Smashrun's FAQ says "3 best per month" while their blog says "rolling 30-day"; we use the rolling 30-day window (§13).
- **Regression:**
  - OLS of SPI against time (days) over the top runs in the window.
  - The band is ±1 SD of the residuals.
  - Weekly change = slope × 7.
- **Pace axes:** linear in speed, labeled as pace. This matches Smashrun's 4:17 / 5:00 / 6:00 / 7:30 / 10:00 / 15:00 / 30:00 axis.
- **Pace variability (Phase 2):** distance covered in consecutive 10 s windows while the timer is running, then mean absolute deviation ÷ mean, as a %.
- **Tracks (Phase 2):**
  - Garmin originals are untrimmed: Garmin applies trims only to the summary. FIT recordings are clipped: records before `started_at` (−2 s) are dropped, then records whose timer time exceeds `timer_s` (+2 s). Clipping to `elapsed_s` cut real data off runs with long pauses, because Garmin's `elapsed_s` can be shorter than the file's wall-clock span. Every FIT track is within 1% of its summary's distance and timer.
  - TCX isn't clipped, because the TCX parser keeps no per-row timestamps. It removes pauses per lap instead: the lap's excess (the time the lap adds to `t`, namely its own gaps plus the gap into its first trackpoint unless that is over 10 s, minus `TotalTimeSeconds`) is taken out of stall gaps (over 10 s, distance advancing under 0.5 m/s), largest first. Garmin's `timer_s` for these imports equals the sum of the laps' `TotalTimeSeconds`; 57 of the 64 TCX runs end within 0.5% of it.
  - `t` is timer seconds with pauses removed, `d` is cumulative metres, and cadence is steps/min for both legs.
  - If the distance series is missing or more than 10% off `distance_m`, `d` is rebuilt at constant pace, and `splits`, `pace_profile` and `pace_variability` stay nil. The run page omits the speed chart for those runs.
  - Zero cadence and zero heart rate count as missing for every format, because recordings carry cadence 0 while stopped (1,741 such points in the 18 sampled FIT and TCX runs).
  - Smashrun's no-GPS marker (`latitude` = `longitude` = −1.0; 1,588 points in 80 of 352 details) becomes a missing position, so route lines don't shoot out to (−1, −1).
  - Smashrun `clock` includes stopped time. The excess of `t` over the row's `timer_s` is removed from stopped intervals (distance advancing under 0.5 m/s), largest first and never more than the excess, with final `d` unchanged. This takes tracks within 2% of `timer_s` from 269 to 332 of 352, and tracks over 15% past it from 31 to 1. `timer_s` is the budget rather than the detail's `duration`, which was the worse match in 54 of the 63 runs where the two differ by over 2%.
  - Per-split elevation gain and loss use a 1 m hysteresis, which is close to Garmin's totals across the sampled runs (single runs are off by up to about 28 m).
  - `Track#bars(100)` gives the 100 m bars of the speed chart.
- **Notables (Phase 2):**
  - Computed on the fly by `Notables.for(activity, runs)`, with no stored column, as of the run's date. Each one shows the largest window that holds ("in 6 months", "ever").
  - The set:
    - Longest run.
    - Fastest run for a similar distance (±10%).
    - Most elevation gain.
    - Hottest or coldest run.
    - During sunrise or sunset (start or end within ±30 min, from Open-Meteo's daily sunrise and sunset).
    - Full moon or new moon.
    - First run at a new Garmin location name.
    - Earliest or latest start.
    - Extends the longest streak.
    - First run of the year.
    - Lifetime distance milestones (every 1,000 km).
    - Race.
  - Windows: 1, 3, 6 and 12 months, and ever.
- **Food equivalents (Phase 2):** a static list of foods with kcal (`Food::ITEMS`), from a banana up to a kremšnita and a pizza. `Food.for(calories)` picks the food whose multiple (1–12) best matches the run's Garmin or Smashrun calories.

## 7. Data sources and sync

### 7.1 Garmin Connect Personal API

- **Base URL:** `https://personal.connectapi.garmin.com`
- **Auth:**
  - Exchange the key in `.env` (`GARMIN_API_TOKEN`) for a bearer token:

    ```
    POST /personalapitoken-service/personal-api/personal-api-key/token
    Authorization: ApiKey <key>
    ```

  - The token is a JWT valid for 24 h. There is no refresh token; you just exchange the key again.
  - Cache the token in `Rails.cache` until `exp − 1 h`.
  - On a 401, re-exchange once. If the exchange itself fails, the key has expired. Garmin keys last 30, 90, 180 or 365 days, and Garmin emails a week before expiry. Show the rotation banner.
- **Client:** a thin `Net::HTTP` wrapper in `app/lib/garmin/client.rb`. No gem; the reference implementation is [garmin/connect-personal-api-python](https://github.com/garmin/connect-personal-api-python).
- **Throttling:** at most 1 request/s, with exponential backoff on 429 or 5xx (up to 5 tries). The rate limits are undocumented and no rate-limit headers were observed. The page size is 100: `limit=250` returns HTTP 500. All writes are idempotent upserts, so restarting is always safe.

| Endpoint | Used for | Phase |
|---|---|---|
| `GET /activitylist-service/activities/search/activities?activityType=running&start&limit&startDate&endDate` | All run summaries (paged, page size 100) | 0 |
| `GET /activity-service/activity/{id}` | Summary refresh when needed | 0 |
| `GET /userprofile-service/userprofile/settings` | Profile (birth date for notables) | 0 |
| `GET /download-service/files/activity/{id}` | Original file as a ZIP: one `.fit` (watch runs) or one `.tcx` (2017 bulk imports). Untrimmed, so FIT recordings are clipped (§6). | 2 |
| `GET /biometric-service/heartRateZones/v2` | HR zones (Pro Map, Training Bands) | 3 |
| `GET /usersummary-service/v2/dailysummaries?startDate&endDate` | Resting HR | 4 |
| `GET /hrv-service/hrv/daily/{from}/{to}` | HRV | 4 |
| `GET /sleep-service/sleep/dailySleepSummariesByDate?startDate&endDate` | Sleep | 4 |
| `GET /weight-service/weight/range/{start}/{end}?includeAll=true` | Weight | 4 |
| `GET /wellness-service/wellness/bodyBattery/reports/daily?startDate&endDate` | Body Battery | 4 |
| `GET /usersummary-service/stats/stress/daily/{start}/{end}` | Stress | 4 |

The Personal API has **no** time-series, splits, laps, weather or HR-time-in-zone endpoints. Everything per-second comes from the original file (Phase 2), or from Smashrun for the years before Garmin (§7.5), and weather comes from Open-Meteo.

### 7.2 Sync flow

- **Backfill:** page through the activity search newest to oldest until a page comes back empty, upserting by `(source, external_id)`. About 30 requests cover the whole history.
- **Incremental:** page newest-first until a full page is all already-known IDs.
- **Full resync:** a rare manual action. It re-pages everything, picks up edits to old activities, and deletes local Garmin runs that no longer exist on Garmin.
- **Triggers:** opening the app (if the last sync was more than 30 min ago) and the **Sync now** button. Both call `Activity.sync_later` → `Activity::SyncJob` → `Activity.sync_now`. Phase 1 uses the default development job adapter, which is fine because the sync is idempotent.
- **Originals (Phase 2):**
  - `bin/rails activities:download` is the one-time backfill: about 2,514 files at ≤ 1 request/s (about 45 min of downloads), in the foreground with progress output. FIT parsing is slower than the download (2–8 s per file), so the whole run takes hours single-process. The class methods respect relation scoping, so split it across processes, for example `Activity.where("activities.id % 4 = ?", k).download_originals` in 4 `bin/rails runner` processes. Each process throttles itself to 1 request/s, so together they exceed 1 request/s: the real backfill averaged about 1.6 requests/s with 4 processes and saw no errors.
  - The sync downloads the original of every run it pages through that has none, processes a run that has an original but no track, and reprocesses a run whose `started_at`, `timer_s` or `distance_m` changed, which picks up trims. A failure for one run is logged and skipped, and the next sync retries it. The sync refreshes `sync_started_at` after each run, so a long sync keeps counting as running.
  - `bin/rails activities:reprocess` rebuilds all derived data from stored originals whenever the algorithms change.
- **Weather:** each sync also fetches weather for runs 6–60 days old that still have none, because the archive lags about 5 days. `bin/rails weather:fetch` is the full backfill.
- **Phase 4 wellness:** date-range endpoints in 30-day chunks, from the first run date onward. Incremental syncs re-fetch from the last stored date − 3 days, because Garmin fills in late data.

### 7.3 Strava gap fill (Phase 0, one-time)

`bin/rails strava:fetch` is the source: it asks for `activity:read_all` in the browser, pages through `/athlete/activities`, and applies the cutoff below. The API gives each run's real local time and its race flag. `start_date` is UTC and `start_date_local` is wall-clock time with a `Z` suffix, so both are parsed as UTC. The archive import stays as a fallback: request the archive from Strava (*Settings → My Account → Download or Delete Your Account → Request your archive*), unzip it, and run `bin/rails strava:import[~/Downloads/export_xxx]`, which reads `activities.csv` and takes rows whose type matches `/run/i`.

1. **Cutoff:** Garmin is authoritative from its first run on. Rows that start later than 10 minutes before the first Garmin run are skipped, so sync Garmin first; the tasks refuse to run without Garmin runs. Matching each Strava run against Garmin runs was tried first, but every Strava-only "run" inside Garmin's history turned out to be a hike Garmin recorded as hiking (78) or a second copy of a run (1). The task prints a report of imported and skipped rows.
2. Imported runs get `source: "strava"` and link out to Strava.
3. Tracks come from Smashrun (§7.5).

### 7.4 Weather (Phase 2)

- Source: the Open-Meteo historical archive API (free, no key).
- Fetch hourly temperature, humidity, wind and precipitation at the run's local midpoint hour, plus the daily sunrise and sunset, with `timezone=auto`.
- Coordinates are rounded to 0.01° before sending.
- Results are cached on the activity.
- Treadmill and indoor runs, and runs without start coordinates, get no weather.
- The archive lags about 5 days. When it returns nulls, `weather` stays nil and a later sync retries it (§7.2).

### 7.5 Smashrun (Phase 2)

Smashrun supplies tracks for the runs before Garmin, and the one run that exists only there. It replaces the Strava streams and the Smashrun bulk export, which aren't used.

- **Login:** `POST https://secure.smashrun.com/services/apiauth-jsonservice.asmx/ConnectUserLogin` with `SMASHRUN_USERNAME` and `SMASHRUN_PASSWORD` from `.env`. It returns a 12-week token for the documented API. `info.message` reads "An unexpected error occurred on the server" even when the login succeeds, so check `isFailed` and that a token is present. The token is held only in memory.
- **API:** `https://api.smashrun.com/v1` with a bearer token. User-level tokens are limited to 250 requests per hour, so the client spaces calls 15 s apart.

| Endpoint | Used for |
|---|---|
| `GET /my/activities` | All summaries in one response (`page` and `count` are ignored) |
| `GET /my/activities/{id}` | The summary plus `recordingKeys`/`recordingValues` (series-major: `distance` in km, `latitude`, `longitude`, `elevation`, `heartRate`, `cadence` per leg, `clock` in s including pauses), `pauseIndexes`, `laps` |

- **`bin/rails smashrun:fetch`:**
  - Keeps summaries that start more than 10 min before the first Garmin run.
  - Matches each to the nearest activity by local wall clock (`local_started_at` against `startDateTimeLocal` with the offset ignored) within ±10 min, because Smashrun's UTC offset is wrong on some runs. The Garmin-era cutoff still compares UTC. A match gets its nil `calories` filled and `race` ORed with Smashrun's flag.
  - An unmatched run is created with `source: "smashrun"`. Exactly one is expected: 3 Mar 2015, 8.00 km, treadmill.
  - Every matched or created run gets its details stored as `smashrun-<id>.json.gz` (the response body, gzipped) and processed.
  - Resumable, and it prints a report.
- **Coverage:** 354 pre-Garmin runs. 353 match Strava rows and all 354 have details, 353 with GPS. Two details (Smashrun `6093331` and `5850866`) have null recordings, so those two Strava runs have no track. The Smashrun-only treadmill run's distance series is unusable (0.18 km against 8.00 km), so it falls back to the summary distance.
- **Garmin-era cutoff:** Smashrun runs from Garmin's first run onward are ignored. Garmin is the source of truth there: 75 are Smashrun-only (71 Garmin hikes, 3 runs under 100 m, 1 file deleted from Garmin).
- **Known data quirk:** the 2017 iSmoothRun treadmill TCX imports have sparse trackpoints and inconsistent Garmin summaries. For example, `1757716207` ends with track `t` 2,501 s against `timer_s` 2,830.

## 8. Data model (SQLite)

### `activities` (Phase 0)

| Column | Notes |
|---|---|
| `source` | `garmin`, `strava` or `smashrun`. Unique with `external_id`. |
| `external_id` | Garmin, Strava or Smashrun activity ID. |
| `started_at` | UTC |
| `local_started_at` | From `startTimeLocal`. Used for all day bucketing. |
| `name` | |
| `activity_type` | Garmin type key: `running`, `trail_running`, `treadmill_running`, … |
| `indoor` | true for treadmill, indoor and virtual |
| `race` | true when the event type is `race` |
| `distance_m`, `timer_s`, `moving_s`, `elapsed_s` | |
| `elevation_gain_m`, `elevation_loss_m` | |
| `avg_hr`, `max_hr`, `avg_cadence`, `max_cadence`, `calories`, `vo2max` | All nullable; older runs lack some of these. |
| `start_lat`, `start_lng`, `location_name` | |
| `spi`, `vdot` | Computed on save |
| `summary` | JSON: the raw Garmin summary or Strava CSV row, so fields can be re-derived without re-fetching. |

Index on `local_started_at`. All of history is about 2,900 rows. Aggregations load the period's runs into Ruby; add caching only if measurements show a need.

### Phase 2 additions

- On `activities`: `has_one_attached :original` (Active Storage, local disk). Columns `splits` (JSON, per km), `pace_profile` (JSON, 20 values for the sparkline), `pace_variability` (float), `weather` (JSON: temperature, humidity, wind, precipitation, code, sunrise, sunset). The original is the Garmin ZIP as downloaded (`<id>.zip`) or the gzipped Smashrun detail (`smashrun-<id>.json.gz`).
- `tracks`: `activity_id` (unique) and `data` (JSON of columnar arrays `t, d, lat, lng, alt, hr, cad`, downsampled to ≤ 2,000 points; series without data are omitted). Tracks live in a separate table so loading activities stays lean.
- No `notables` column: notables are computed on the fly. `efforts` (fastest segments) moves to Phase 3 with the Pro Map.

### Phase 3 additions

- `activities.bands`: JSON of seconds per pace bucket, HR zone and grade bucket.
- `goals`: `period` (month or year), `starts_on`, `distance_m`.

### Phase 4 additions

- `wellness_days`: `date` (unique), `resting_hr`, `hrv_avg`, `hrv_baseline_low`, `hrv_baseline_high`, `sleep_s`, `sleep_score`, `body_battery_high`, `body_battery_low`, `stress_avg`, `weight_kg`, and `raw` (JSON per endpoint).

### Singleton `profile`

Garmin profile and HR zones (JSON), `synced_at`, `sync_error`.

## 9. Architecture and stack

- **Generator (Phase 0):**

  ```
  rails new . --name=smashback --css=tailwind --skip-kamal --skip-thruster --skip-docker --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-jbuilder --skip-system-test
  ```

  This keeps the Rails defaults: SQLite, Importmap, Propshaft, Hotwire, Solid Cache/Queue/Cable, RuboCop omakase, Brakeman, `bin/ci`.
- **Gems:**
  - `dotenv`: Rails doesn't load `.env` on its own.
  - Tests: `factory_bot_rails`, `webmock` (as in Visualizer).
  - Phase 2: `rubyzip` (Garmin downloads are ZIPs) and `fit4ruby` from your fork `miharekar/fit4ruby` (§3). Nokogiri, already bundled, parses TCX.
  - `csv` for the Strava import.
- **JS (Importmap only, no Node build):**
  - `bin/importmap pin d3` in Phase 1.
  - Mapbox GL JS in Phase 2, the single-file UMD build vendored in `vendor/javascript` with its CSS (`app/assets/stylesheets/mapbox-gl.css`), pinned with `preload: false` and imported dynamically so only run pages with a map load it. The multi-chunk ESM build breaks under Propshaft's digested paths. Every map, including the Phase 3 Pro Map, uses it.
- **Code organization (Visualizer `STYLE.md`):**
  - Rich models with thin controllers.
  - Class-scoped concerns, for example `Activity::Performance` for SPI/VDOT, `Activity::GarminSync`, `Activity::StravaImport`.
  - POROs in `app/models` for aggregates: `Overview`, `PersonalRecords`, `PaceTrend`, `PrProgress`.
  - Integrations in `app/lib`: `Garmin::Client`, `Strava::Client`, `Smashrun::Client`, `OpenMeteo::Client`.
  - Jobs follow the `_later`/`_now` pattern.
- **Routes:** REST resources only:
  - `resource :overview` (with `:year`/`:month`), `resource :pace_trend`, `resource :pr_progress`, `resource :sync` (`create` = Sync now).
  - `resources :runs` (index and show) since Phase 2.
  - Later: `resource :training_bands`, `resources :goals`, `resource :wellness`.
- **Charts:**
  - One Stimulus controller per chart type: `period-bars`, `trailing-line`, `pace-scatter`, `weekly-heatmap`, `pace-trends`, `pr-progress`, and so on.
  - The server renders chart data as JSON into Stimulus values, so Phase 1 needs no JSON endpoints.
  - Shared helpers live in `app/javascript/helpers/charts/`: pace and duration formatters, axes, tooltip, brush.
  - Charts redraw on `ResizeObserver`.
  - Theme comes from CSS variables (`--chart-accent`, `--chart-muted`, `--chart-grid`, …), so a light/dark switch needs no redraw.

## 10. Design

- **Theme:** light and dark via `prefers-color-scheme` (Tailwind v4's default `dark:` behavior).
- **Palette:**
  - Accent is a nod to Smashrun's "Team Yellow Green": lime/green (dark mode base `#6ACD12`, highlight `#9CFF44`, low `#254806`; deeper greens in light mode).
  - Amber/yellow for highlighted "top runs" and predictions.
  - Neutrals from Tailwind `zinc`.
- **Layout:**
  - `max-w-7xl`. Cards with subtle borders. Two columns on desktop, one on narrow screens.
  - Chart titles hold their metric switches inline, as Smashrun did ("**Distance** ▾ per month").
- **Type:** the system UI font stack. `tabular-nums` for stats. Units are small and muted next to big numbers.
- **Motion:** 150–250 ms transitions on chart updates and nothing more.

## 11. Privacy and security

- **Data sensitivity:** the app stores GPS tracks, which reveal home and routines, plus heart-rate and wellness data. It is your own data, kept on your machine.
- **Network exposure:** the dev server binds to 0.0.0.0 and allows the hosts `framework:3000` and `test.rekar.eu`, all behind Tailscale. There is no auth, so the tailnet is the boundary.
- **Secrets:** `.env` is ignored by Rails' default `.gitignore` (`/.env*`) and is mode 600.
- **Smashrun credentials:** `SMASHRUN_USERNAME` and `SMASHRUN_PASSWORD` grant full access to the Smashrun account. Never log them. The 12-week token is held only in memory.
- **Garmin key:** the key gives read access to all of your Garmin health data. It must never be logged; filter it and the bearer token out of logs and error output.
- **Key rotation:** create a new key at `connect.garmin.com/app/settings/personalApiToken`, update `.env`, and restart.
- **Storage:** `storage/` (SQLite databases and the stored originals) is git-ignored by default. If you back it up, encrypt the backup.
- **Third parties:**
  - Garmin (the source).
  - Strava (gap fill, once).
  - Smashrun (until it shuts down): receives your login, once per fetch.
  - Open-Meteo (Phase 2): receives rounded coordinates and dates.
  - Mapbox (Phase 2): receives the style, tile and font requests, which reveal which areas you view, and the public token. With `performanceMetricsCollection: false` (GL JS sends `gljs.performance` events with the user agent, screen size and GPU by default), the only events still sent to `events.mapbox.com` are `appUserTurnstile`, `style.load` and `map.load` (the one Mapbox bills on, one per map initialised on a page). They carry the SDK version, the style URL, the token-derived SKU token and an anonymous user ID that GL keeps in `localStorage` (keys starting `mapbox.eventData`).
  - No analytics.
- **Terms:** Garmin's Personal API is for personal use only. Turning this into a multi-user app would mean handling other people's health and location data. That would require Garmin's business developer program and real privacy and compliance work. It is out of scope.

## 12. Testing and acceptance

**Test suite**

- Minitest, FactoryBot, and WebMock with the network disabled.
- Fixtures are synthetic: made-up coordinates, names, IDs and heart rates. Nothing downloaded from your accounts goes into `test/`.

**Unit tests**

- SPI/VDOT golden values.
- PR bucketing and interpolation.
- Streaks and breaks.
- Trailing sums.
- Weekly buckets.
- Magic PR targets.
- Top-run flagging.
- Predictions: SPI uses the closed form; the Ruby lookup tables are interpolated in the browser.
- Garmin client: token caching, re-exchange on 401, expired-key error.
- Sync: idempotent upsert, delete reconciliation.
- Strava gap-fill cutoff.
- Phase 2:
  - Track parsers (FIT, TCX with two `<Track>`s, Smashrun JSON) and metrics: splits, pace profile, variability, clipping, cadence doubling, the 2,000-point cap.
  - Smashrun import: cutoff, nearest match, creation, race OR, calorie fill.
  - Weather, notables (one per type, moon phase on known dates), food picker.
  - Garmin original download and the sync hooks.

**JS tests**

`node --test` for the regression, brush stats, formatters, run stats and Analyze Run helpers.

**Golden values**

Smashback's values, next to smashrun.com/miharekar (all time, km). Smashrun used its own processing and counts about 470 km of hikes that Garmin recorded as hiking. Streaks and breaks must match exactly; totals and PRs within ±0.1%.

| Metric | Smashback | Smashrun |
|---|---|---|
| Runs | 2,868 | 2,942 |
| Total distance | 32,974.3 km | ≈ 33,464 km |
| Most often run on | Saturday: 455 days, avg 14.8 km | Saturday: 469 days, avg 14.7 km |
| Least often run on | Friday: 349 days, avg 10.2 km | Friday: 350 days, avg 10.2 km |
| Average run length | 11.5 km | 11.4 km |
| Runs after noon | 67% | 66% |
| Average pace | 6:07 /km | 6:14 /km |
| Longest run | 43.2 km on 25 Sep 2016 | same |
| Longest break | 110 days (30 Oct 2014 – 16 Feb 2015) | same |
| Longest streak | 111 days (21 Apr – 9 Aug 2020) | same |
| PR 5 km | 24:23 (12 Apr 2022) | same |
| PR 10 km | 42:44 (14 Oct 2019); bucket of 1,098 runs | 42:45; bucket of 1,104 |
| PR half marathon | 1:37:34 (24 Mar 2019, race) | 1:37:30 |
| PR marathon | 3:20:40 (22 Oct 2023, race) | 3:20:32 |

**Performance**

- Overview, all-time view: under 300 ms server time on the full history.
- Brushing Pace Trends and PR Progress stays smooth: no recompute over ~16 ms on ~2,900 runs.

## 13. Risks and open questions

| # | Item | Plan |
|---|---|---|
| R1 | FIT parsing in Ruby. | Spiked on 16 FIT files from 2018 to 2026: the fork parses all of them with its post-read `Activity#check` validation no-oped, matching Garmin's distance and timer. Later, with all runs processed, every FIT track is within 1% of its summary. `fit_kit` doesn't build on Ruby 4.0.9. About 2,000 records/s, so a full backfill needs several processes (§7.2). |
| R2 | Personal API rate limits are undocumented. The maximum `limit` is 100 (250 returns HTTP 500). | Verified: no 429s in a full backfill at 1 request/s. Throttle and back off anyway. |
| R3 | Does `activityType=running` include child types such as treadmill and trail? | Verified: it includes `trail_running`. Treadmill runs are typed `treadmill_running`. |
| R4 | Purdy constants and table fidelity. | Golden tests against published Purdy tables before building the charts. |
| R5 | Strava CSV quirks. | Moot: the Strava API is the primary source (§7.3). |
| R6 | Personal API key expiry (≤ 1 year). | Clear banner and rotation docs (§11). |
| Q1 | Smashrun Pro's "Trends Comparison": what did it do? | Unknown. Skipped unless you remember. |
| Q3 | Top runs: rolling 30-day window or calendar month? | Rolling 30-day chosen. It's a one-line change. |
| R7 | Smashrun shutting down. | Its data is fetched once into stored originals (§7.5), so nothing depends on it afterwards. |
| R8 | Garmin originals are untrimmed. | Clip FIT recordings to `started_at` and `timer_s` of recording time (§6). |
| R9 | The Open-Meteo archive lags about 5 days. | Leave `weather` nil and retry on later syncs (§7.2). |
| Q4 | Garmin Connect web URL for activities. | `/app/activity/:id`. |

## 14. Checklist

Phase 0 is done.
