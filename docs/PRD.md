# Chartlek: Product Requirements Document

- **Status:** all planned work is built and deployed.
- **Owner:** Miha Rekar
- **Repo:** `~/Projects/Personal/chartlek`
- **Production:** https://chartlek.rekar.eu (a Docker container, §8)

This document specifies the product as built. Coding conventions are in `AGENTS.md` and `STYLE.md`; `README.md` describes the features for humans.

## 1. Summary

Chartlek is a local, single-user Rails app. It caches your Garmin Connect running history in SQLite and rebuilds Smashrun's charts, free and Pro, with a Tailwind UI and charts built directly on D3. It adds per-run HR zones, Garmin wellness data (resting HR, HRV, sleep, Body Battery, stress, weight), Strava gear, weather, terrain maps, Training Bands, goals and a Pro Map. It runs as a container at chartlek.rekar.eu.

Why: Smashrun (smashrun.com/miharekar) is effectively abandonware, but its charts are still the best way to look at a long running history. The ask in [dreeveapp/dreeve#2880](https://github.com/dreeveapp/dreeve/issues/2880) was turned down because most of these charts are too runner-specific for a general-purpose app. Chartlek is only about running, so it can include all of them.

## 2. Goals and non-goals

### Goals

- **G1:** Every Smashrun overview chart and the Pro analytics: Overview, Pace Trends, PR Progress, the run page, Training Bands, Progress Towards Goal, Pro Map.
- **G2:** Garmin Connect Personal API as the primary source, cached in SQLite. The UI never waits on Garmin.
- **G3:** Fill the years before Garmin from the Strava API; take their tracks, and any Smashrun-only runs, from the Smashrun API.
- **G4:** A fast, modern, consistent UI: Tailwind, a System / Light / Dark switch, D3 charts as Stimulus controllers, one design system (§9) in which every choice among options is a group of buttons.
- **G5:** Garmin health data on runs and in trends: HR zones, training effect and load, resting HR, HRV, sleep, Body Battery, stress and weight (§4.6).
- **G6:** Strava gear, read-only: usage per shoe, and the runs that have no gear set, so they can be fixed on Strava (§4.7).

### Non-goals

- Badges, anything social (friends, ranks, rarity %, invites, sharing), weekly email report.
- Cooper test view.
- Local run tags, notes or edits.
- Power charts, power zones or power-based metrics.
- Multi-user support and authentication. It is deployed for the owner alone (§8).
- Imperial units, including mile benchmarks.
- Writing anything back to Garmin or Strava, including gear.
- Gear maintenance, recording devices, bikes and shoe mileage alerts.
- Smashrun's SPI score and its trailing 90-day SPI comparison. VDOT replaces SPI, and the VDOT view of "Runs in the prior 90 days" covers the comparison.
- Data the Personal API doesn't offer (training readiness, recovery time, training status and load, VO2max), and any Garmin data-export import.
- A mobile app.

## 3. Decisions

| Topic | Decision |
|---|---|
| Users | Just you. Single user, no accounts, no auth: the tailnet is the boundary (§8, §10). |
| Garmin access | [Garmin Connect Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api/); the key is `GARMIN_API_TOKEN` in `.env`. |
| History gaps | Strava API (archive as fallback) for runs before Garmin, plus Smashrun for their tracks and the one Smashrun-only run. |
| FIT parser | Our own decoder, `Track::FitFile` (§4.6, AGENTS.md): it reads only the 17 fields of 4 messages the app uses, as raw integers, about 12 ms a file at p50 in the app (5.6 ms in the prototype walk). `fit_kit` doesn't build on Ruby 4.0.9. No CRC checks, first segment only, and compressed timestamp headers are framed but give no timestamp, so such a record raises; malformed bytes raise `Track::Error`. |
| Maps | Mapbox GL JS for every map (run map, Pro Map), the `mapbox/light-v11` and `dark-v11` styles following the theme (the OS under System), terrain layers on top (§4.5). The public `MAPBOX_TOKEN` from `.env` is rendered into the page. |
| Activity types | All running subtypes: road, trail, track, treadmill, indoor, virtual, ultra. Treadmill, indoor and virtual runs are flagged. |
| Performance index | VDOT only. SPI has no physical meaning, and VDOT predicted the owner's PRs more accurately (§5). Presented the Smashrun way: a zone strip and an estimated finish you can step through the distances. |
| Controls | Every choice among options is a group of buttons (`aria-pressed`). No `<select>` anywhere (§9). |
| Units | Metric only: km, min/km, m, °C, 24h clock, weeks start Monday. |
| Theme | System, Light or Dark; a switch in the nav, stored in a long-lived cookie and rendered on `<html data-theme>` by the server. |
| Stack | Rails 8.1, Ruby 4.0.9 (mise), SQLite, Tailwind, Importmap, Hotwire, D3, Solid Queue, Cache and Cable. Follows Visualizer's `STYLE.md`. |

## 4. Feature specs

### 4.1 Global

- **Nav:** Overview, Runs, Pace Trends, PR Progress, Wellness, Training Bands, Gear, Goals. Items wrap instead of overflowing; no dropdown menus. The Pro Map opens from a run. On the right: the sync status, **Sync now**, **Connect Strava** (or **Reconnect Strava** when the stored grant lacks gear access, §6.5) and the theme switch.
- **Sync status:**
  - Shows "Synced 12 min ago", "Syncing…" live, and the **Sync now** button.
  - A sync runs every hour in the background (a Solid Queue recurring task in the container) and on the button. Opening a page does not sync.
  - A sync that created, changed or deleted runs, or changed the error state, refreshes the page with a Turbo `:replace` refresh (`turbo_refreshes_with method: :replace`). Morphing would wipe the D3-drawn SVGs; a replace makes chart controllers reconnect and redraw. Any other sync only replaces the nav status in place, so no page state (modes, selections, brushed windows) is lost.
  - If the Garmin key has expired, a banner explains how to rotate it (§10).
- **Theme:** a switch is a full page load, because Turbo doesn't update `<html>` attributes.
- **Controls:** a choice among options is a button group with `aria-pressed`; independent filters are toggle buttons; actions are buttons (§9).
- **Formatting:** pace `m:ss /km`; durations `h:mm:ss`; distances one decimal in km everywhere (tooltips included); dates `21 Apr 2020`; numbers `tabular-nums`.
- **Links:** clicking a run in any chart opens its run page in the same tab. The run page links out to Garmin or Strava.
- **Chart info:** every chart has an ⓘ explaining how to read it, adapted from Smashrun's FAQ. The text shows in the shared tooltip on hover, keyboard focus or tap; Escape or a click elsewhere hides it.
- **Empty states:** a page with no runs or no data shows an empty state instead of charts.
- **Keyboard and focus:** a chart's interactive elements are one Tab stop with Arrow, Home, End and Escape. A mouse click on a chart with no click action never leaves a focus outline or pins a tooltip; keyboard focus (`:focus-visible`) shows a ring.

### 4.2 Overview

Routes: `/` → `/overview`, `/overview/:year`, `/overview/:year/:month`.

The period selector offers **All time**, a pill for every year (newest first), and month pills for the selected year (months without runs are disabled). The period applies to every widget. The header has a **Latest run · date · km →** button to the newest run overall (absent without runs).

| # | Widget | Spec |
|---|---|---|
| 1 | Kilometers run | Big total with the number in English words underneath, Smashrun-style. Run count. |
| 2 | Average run length | km |
| 3 | Average days run per week | Distinct run days ÷ weeks in the period. For all time, the period runs from the first run to today. |
| 4 | Time of day | % of runs starting after noon (local time), with a small AM/PM donut. |
| 5 | Average pace | Total timer time ÷ total distance. |
| 6 | Yearly goal | A stat tile beside Kilometers run (§4.10). |
| 7 | Distance per period | Bars: per month (all time), per week (year), per day (month). A button group chooses the metric: **Distance**, Elevation gained, Avg distance, Avg pace, Avg VDOT; the title follows it. Hover shows value and run count. Clicking a bar drills into that period. |
| 8 | Trailing days | Daily rolling sum of distance: 365 days (all time), 90 (year), 7 (month). |
| 9 | Runs pace vs distance | Scatter of the period's runs. x = km; y = pace on a speed-linear axis labelled as pace (ticks 4:00, 5:00, 6:00, 7:30, 10:00, 15:00, 30:00). The last run is a plain amber dot, a little larger than the rest; it hides while a linked hover selection is active. The average is a ring marker. A button group chooses the y metric: **Pace**, Avg HR, VDOT. |
| 10 | Consecutive days run | Longest streak and longest break with dates, plus the current streak or break. |
| 11 | Weekly stats for each year | All time: heatmap with years as rows and Monday-start weeks as columns; weekly km buckets >1, >20, >40, >50, >60 (ring), >80 (dot). Year and month views: a day calendar coloured by daily km. |
| 12 | Personal records | Benchmarks 3 km, 5 km, 10 km, 15 km, 20 km, half marathon, 40 km, marathon, 50 km, 100 km; only those with qualifying runs in the period. Each row: date, pace, km/h, time, runs in the bucket, and a race tag. Below `sm` the km/h and Runs columns are hidden. |

The monthly goal is a compact widget in a row between the period selector and the tiles (§4.10).

**Linked hover (Smashrun-style).** Hovering one of the charts below selects a set of the period's runs and highlights them in the others; leaving clears it. The chart under the pointer keeps its own tooltip and click. Hover also works over a chart's axes and margins: the bars and the trailing line treat the bottom axis as the nearest column or day.

| Hover | Selects |
|---|---|
| Trailing line, at day d | the runs in the N days ending at d (N is the chart's window) |
| Scatter, in the plot | the runs plotted strictly further right and strictly higher (longer, and faster or higher on the y metric) than the cursor |
| Scatter, over the bottom axis | every run longer than the cursor's x, at any pace |
| Scatter, over the left axis | every run above the cursor's y, at any distance; the bottom-left corner selects nothing |
| Distance bars, at the cursor | every run of the column under the cursor (the full chart height counts, gaps snap to the nearest bar); that bar stays at full opacity and the others dim |
| Heatmap cell | the runs of that week (all time) or day |
| Heatmap legend bucket | the runs in every cell of that bucket |
| Longest / current streak or break | the runs in that span (none for a break) |

| Chart | Shows the selection as |
|---|---|
| Scatter | selected dots in the highlight colour, the rest faded and muted; the average ring (and the legend's ring) moves to the selection's mean (km-weighted pace, plain mean of HR and VDOT) and thickens. An empty selection keeps the ring where it was |
| Bars | the selection's share inside each bar (by km for Distance, metres gained for Elevation, run count for the averages) over a faded bar |
| Heatmap | every cell outside the selection faded (a streak or break fades the cells outside its dates; hovering a cell itself fades nothing) |

The selection is only for the current view, is published through one shared module that redraws just the highlight layers once per animation frame, and is mouse driven.

### 4.3 Pace Trends

Answers "am I getting faster?" by putting all distances on a common scale (VDOT).

**Main chart**

- x = date, y = VDOT. Every run is a small muted dot.
- **Top runs** are accent dots joined by a faint smoothed line. A run is a top run if it is in the top 3 by VDOT within the 30 days ending on its date (§5).
- A **regression band** shows the least-squares line through the top runs inside the window, ±1 SD of the residuals.

**Timeline and window**

- Below the chart, a timeline of bars shows each run's duration in hours over the whole history. A `d3-brush` on it selects the window; the default is the last 12 months. The main chart zooms to the window.
- **Presets:** a button group sets the window in one click: 3 mo, 6 mo, 1 yr, 2 yr, All time. Each ends at the date of the latest run and starts that many calendar months earlier, clamped to the month's length; All time starts at the first run, and a span longer than the history also starts there (the longer preset is then the one marked). The preset matching the window has `aria-pressed`; the default marks 1 yr. A drag or resize clears the mark unless the new window equals a preset exactly. The window is in the `from` and `to` URL params, so reloads, links and filter chips keep it. PR Progress has no presets.
- The header shows the date range, "Change in VDOT: **+0.05/week**" (slope × 7, two decimals) and "Cut **34:28** from your estimated **5K / 10K / Half / Marathon** finish time" (distance is a button group): the predicted time at that distance from the regression VDOT at the start of the window versus the end; negative reads "Added".
- The regression and header are recomputed in the browser while dragging.

**Filters** (toggle buttons): Exclude pauses (`no_pauses`), Races only (`races`, Garmin event type `race`).

**Tooltip:** date, name, VDOT, distance, pace and time. Clicking a run opens its run page.

**Overlay:** a button group above the chart chooses None (default), Resting HR, HRV or Sleep, drawn as a thin muted line on a secondary right-hand axis fitted to the window (follows the brush). Resting HR is the 7-day average, HRV the nightly value, Sleep the night's hours (the night before the run's day); a missing day is a gap. The tooltip gains a line with the value for the run's day; regression, stats and predictions don't change. An option appears only when `WellnessDay` has that series, and the group is hidden without wellness data. The choice is the `overlay` URL param (`rhr`, `hrv`, `sleep`; unknown means None), kept by the preset, brush and filter links. All series are in the page payload, so switching needs no request.

### 4.4 PR Progress

**Main chart**

- x = distance on a log scale; y = pace on a speed-linear axis, faster at the top. All runs are muted dots.
- An **all-time frontier** line runs through the benchmark PRs (§5).

**Timeline brush**

- Below the chart, a timeline of runs per day with a brush. Selecting a window draws a second line: the best performance at each benchmark among runs in that window. Dragging scrubs through history, showing how long it has been since you ran or set a PR at each distance.

**"PRs you can beat"**

1. Pick a reference period: last 30, 60 or 90 days.
2. The reference run is the run with the highest VDOT in that period; clicking another run changes it.
3. The chart draws the predicted time at each benchmark at the same VDOT, from the VDOT time tables.
4. Predictions that beat the all-time PR are highlighted. Tooltips show predicted time, pace and % improvement over the current PR.

**"Magic PRs"**

1. For each benchmark, the target is the next round time below the current PR.
2. Steps: 1 min for distances ≤ 5 km, 5 min up to the half marathon, 15 min for longer (5 km 24:23 → 24:00, half 1:37:30 → 1:35:00, marathon 3:20:32 → 3:15:00). The step table is a constant (`PrProgress::Magic`).
3. The 3 targets with the smallest % gap are pulsing markers, with tooltips like "Sub-3:15 marathon: shave 5:32 (2.8%)".

### 4.5 Runs list and run page

**Runs list (`/runs`, filterable by year, month and `gear`)**

- Sortable table: date, name, km, pace, elevation (any other `sort` falls back to date), then one Tags & gear cell.
- Race, PR (Garmin's own personal-record flag, `pr` in the summary), workout and treadmill tags, then the gear tag (§4.7), in one cell: side by side, stacked when the column is cramped. A run is a workout when its summary has an `INTERVAL_WARMUP`, `INTERVAL_RECOVERY`, `INTERVAL_REST` or `INTERVAL_COOLDOWN` split, or an `INTERVAL_ACTIVE` with `noOfSplits` above 1; Garmin's single whole-run `INTERVAL_ACTIVE` on plain runs is not one. The list reads it from a computed `garmin_workout` column.

**Run page (`/runs/:id`)**, top to bottom:

1. **Header**
   - Local date and time, start-end clock time. The date, gear and weather lines share one type and colour (`WidgetsHelper::HEADER_LINE`).
   - Gear line under the date: a sneaker icon and the gear name linking to that gear's runs list, or an amber "No gear" link to `/runs?gear=none`. Runs without a `strava_id` have none.
   - Weather from Open-Meteo at the run's midpoint hour, one line of icon and value items: the condition from the WMO code with its label (clear and partly cloudy turn to a moon outside sunrise to sunset), then temperature, humidity, wind and, only above 0, rain (`14°C`, `60%`, `8 km/h`, `1.2 mm`). The words are `sr-only`, the icons decorative, a missing field leaves no item; runs without weather show nothing.
   - Location name (Garmin only), previous/next run, and Open in Garmin (Garmin runs) and Open in Strava (runs with a `strava_id`, §6.5) buttons. A Smashrun-only run has neither.
   - A switcher between several runs of the same day.
   - A Smashrun-style date navigator: every year with runs (newest first), the 12 months of the run's year, every day of its month, with the run's year, month and day selected. A year or month with runs opens its latest run, a day its first run; the others are inert. Weekends look distinct, race days are amber, and hovering or focusing a day shows weekday, date and distance in the shared tooltip.
   - **Notables** (§5) as compact chips under the header, wrapping on narrow screens; each carries its full text; none shows nothing.
2. **Tiles and cards**, a grid of 4 columns on wide screens and 2 on narrow ones:
   - Distance; elapsed/timer/moving time; average pace and speed. A positive `avgGradeAdjustedSpeed` in the summary adds a "GAP 5:02 /km" line under the speed, with an ⓘ (`Activity::Performance#grade_adjusted_pace`, s/km). The title carries a PR chip beside the race chip when Garmin flagged the run.
   - Calories with a food equivalent.
   - Average HR (min-max) and average cadence (min-max).
   - **Performance index and estimated finish:** one card, two columns wide, in two halves.
     - Performance index (ⓘ with the VDOT explanation, §5): the run's VDOT as the big number (one decimal, a dash without one) and under it a strip of the pace zones (§5) that matter for this runner: the performance-strip range, not all 37 zones. A dot marks the zone of the pace at which this VDOT would run a 5K, labelled with that pace ("5K pace 4:52 /km"); a zone's label shows on hover.
     - Estimated finish: the predicted time at this VDOT for one distance at a time: the time big (h:mm:ss), the distance label (5K, 10K, Half, Marathon) and the pace it implies. A ▶ button steps to the next distance and wraps from Marathon to 5K; the default is 5K and the time is `aria-live="polite"`. All four times are on the page, so stepping makes no request.
     - A run without a VDOT (under 400 m) shows dashes and no strip.
   - **Pace variability**, Smashrun's wheel: a ring of equal-angle wedges, clockwise from 12 o'clock, one per whole 100 m of the run (the same bars as the speed chart; a final shorter bar is dropped, no grouping or cap), all accent colour, with the stored variability % in the hole. A wedge's outer radius is |speed − mean| ÷ mean plus a 0.25 base, over a domain of 0 to the larger of 0.75 and the largest value. Hover or focus shows the wedge's distance range, pace and signed "Speed vs average"; the wheel is one Tab stop (Arrow, Home, End, Escape). Needs at least two whole bars; runs without a track show the percentage and "Recording chart not processed yet."
   - **Nth longest run** and **Nth fastest for a similar distance** (±10%), each with a histogram: distance in km across all runs, or pace in min/km across the similar-distance cohort. Bar height is run count; amber marks the current bucket and exact value. Hover shows range, count and current value. Ties share a rank; cohorts include all dates. Bins are equal-width over the 2nd to 98th percentile (at most 12), with open-ended first and last bins labelled "<x" and ">y" (§5).
   - **Elevation profile** (when the run has altitude or an elevation gain; without altitude it is titled "Elevation" and has no chart): a 70 px line chart of altitude against distance (about two thirds) beside gained (+m), lost (−m) and **hill difficulty** (§5). No axes or grid; the y domain is the low point − 5 m up to the larger of low + 150 m and the high point, so a flat run looks flat; an amber dot marks the highest point. Hover snaps a dot to the nearest sample. There is no separate Elevation tile.
   - **Packing rule:** the grid packs without empty cells at the base, `sm` and `lg` breakpoints, with or without HR, cadence, altitude, pace variability and VDOT.
3. **Route map:** after the tiles, a Mapbox GL JS route line, 600 px tall on desktop and 320 px on phones. Requires a GPS route and the public Mapbox token. Terrain below the roads and labels: subtle hillshading, contour lines (stronger index contours with elevation labels in metres) and mountain peaks as ▲ with name and elevation; the route and its start and end markers stay on top. No toggle. An **Open Pro Map** button opens §4.8.
4. **Change in speed over route:** only for tracks with splits. Bars per 100 m, switchable to per-km splits with a two-button toggle. Brushing a range shows a summary: distance, time, pace, HR, cadence.
5. **Elevation, HR and cadence charts:** 180 px each, sharing the distance x-axis; they require a track. **One distance cursor** ties the page together: hovering the speed chart, the profiles (elevation, HR and cadence share one line and their readouts) or the elevation profile card draws a vertical amber line at that distance on all of them and moves an amber marker along the route map (no panning or zoom). Each chart keeps its own tooltip; leaving clears the line and marker. Runs without a map (indoor) still sync the charts.
6. **Workout** (workouts only, with or without a track): one row per step type in order (warm-up, active, recovery, rest, cool-down) with "×N" when Garmin counts more than one, distance (a dash for none), time and pace (a dash under 100 m). The ⓘ says Garmin gives totals per step type, not per rep. When the track has steps (`chart_metrics["steps"]`, from the FIT laps of a workout run: laps with an intensity, at least two different ones, contiguous over the recording; 2019 workouts have none), the rows carry the step colour swatches and the speed, elevation, HR and cadence charts show a step strip along their top (hover or drag it for the step's distance, time and pace), a faint tint behind active steps (not on HR, which gets thin step dividers), and the step name in the speed tooltips and the profiles readout.
7. **Heart rate zones and effort, Going in** (§4.6).
8. **Fastest runs for this distance:** for the last 90, 180 and 365 days and all time (five rows each, the current run highlighted when listed).
9. **Runs in the prior 90 days** (the Analyze Run view, following Smashrun's layout). The window runs from midnight 90 days before the run's day up to the run's start. This run is never part of the averages or readouts.
   - **Title row:** the title with an ⓘ, and a metric button group: Distance (default), Pace, VDOT, Heart rate.
   - **Dot strip:** a one-dimensional dot plot across the full width. Each previous run is a semi-transparent circle on the metric's axis, so overlaps read as density; this run is a smaller amber dot on top; a thin accent bar marks the mean of the previous runs. Runs without the metric are skipped (zero or missing HR is missing). Axes include this run's value: distance 0 to the longest run rounded up, plus 1 km; pace as speed, from 4 km/h (lower only if a run is slower) to the fastest plus 1 km/h, labelled as pace, faster to the right; VDOT lowest − 1 to highest + 1; heart rate lowest to highest, rounded out to 10 bpm. About seven ticks. Switching the metric glides the dots (about 400 ms); runs without the new metric fade out.
   - **Brush:** dragging across the strip selects the runs whose value is inside it. Others dim, the mean bar hides, the axis shows only the two edge values, and the matching days light up in the timeline. A readout floats above the brush; clicking it cycles four views: share of previous runs (a whole percent, default), hours, distance, run count. Clicking outside the brush, or Escape, clears it. A summary line under the title (run count, distance, duration, share of the window's training distance, for the selection or all runs) is also the text equivalent for assistive tech.
   - **Timeline:** one mark per run day from 90 days before to the run's day, each one day wide and full height; this run's mark is amber at the right edge. Ticks read "90 days before", "60 days before", "30 days before" and "run day" ("race day" for races); under about 140 px per label only the first and last show. A day with earlier runs and this run splits its column: earlier on the left half, this run on the right. Hovering a day highlights it and shows the date, "N days before" (or "yesterday") and each run that day with distance and pace; the matching dots light up (with a brush active, only those inside it). Clicking a day opens its first run.
   - **Dots:** hover shows date, distance, pace, HR and VDOT; a click opens the run, a click on empty strip clears the brush. The strip is one Tab stop; Left, Right, Home, End move between dots in value order (the tooltip follows) and Enter opens the run.
   - **Legend** (hint style): a dot for "This run", a bar for "Average", a large dot for "Previous runs". With no runs in the window it says "No runs in the 90 days before this one."

### 4.6 Wellness

Garmin health data in three places: the run page, a Wellness page and Pace Trends (overlay, §4.3). Available from the Personal API: resting HR, HRV, sleep, stress, Body Battery, weight and HR zones. Not available (so not shown): training readiness, recovery time, training status and load, VO2max (no run summary carries `vO2MaxValue` either).

The stored activity summaries already carry, per run: time in each HR zone, aerobic and anaerobic training effect with its label, training load, Body Battery change, intensity minutes, and running dynamics when the watch records them (ground contact time, vertical oscillation, stride length, vertical ratio).

**HR zones**

- Zones are per run, in `activities.hr_zones`: `floors` (five bpm floors), `max_hr`, `seconds` (zones 1 to 5) and `source` (`fit` or `estimated`). Garmin's zones move with resting HR, and every FIT original carries the zones in force (the session `time_in_zone` message), so each run keeps its own. `Track::FitZones` reads them from the FIT through the same decoder as the track (`Track::FitFile`): message 216 fields 0, 2 and 6, the first message whose type is 18 (session). A truncated or corrupt file reads as no zones, so the run falls through to the estimate. An undefined sixth floor (255) is kept as `max_hr` 255, not rejected; an undefined floor among the first five or an undefined seconds value rejects the set.
- Runs with HR but no FIT zones (the runs before the first FIT, and any later file without the message) get an `estimated` set: the per-floor median of the 100 FIT sets nearest before the run (the earliest 100 when fewer come before it) and seconds from the stored track. Their card shows an Estimated zones chip and a note ("before your watch recorded its zones" or "no recorded zones").
- Floors and seconds are decided separately: floors from the FIT when valid, else the estimate; seconds from the FIT when any is positive, else from the track. A run keeps its floors even when its seconds are all zero (the card then hides). A truncated or corrupt file reads as no zones and falls through to the estimate.
- `HrZones.for(run)` returns a run's zones. `profiles.hr_zones` (Garmin's current running zones from `GET /biometric-service/heartRateZones/v2`, refreshed by the wellness sync) and `HrZones.current` (else Garmin's default 50/60/70/80/90% bands of the highest recorded max HR) are only the fallback for a run without HR.
- `HrZones` turns a bpm into a zone and a zone into its bpm range (`HrZones#range`, `#bands` for the chart).

**On the run page** (after the elevation, HR and cadence charts)

- **Heart rate zones and effort:** one stacked horizontal bar of time in zones 1 to 5 (the run's stored seconds), with each zone's minutes, percent and bpm range under its label (Z1 to Z5 on phones). The bar has a text equivalent (its `aria-label` lists every zone) and is one Tab stop (Arrow, Home, End, Escape; the shared tooltip follows). Zone colours are `--hr-zone-1` to `--hr-zone-5` (blue, green, yellow, orange, red; one set for light and one for dark). Below the bar: aerobic and anaerobic training effect (0 to 5, with Garmin's label under the aerobic one), training load, Body Battery change, intensity minutes, and a running dynamics row only when recorded (ground contact, vertical oscillation, stride length, vertical ratio, and running power and normalized power in W from `avgPower` and `normPower`). A field the run lacks, or with a zero value, is left out. The card shows for every run with HR and zone times (from the stored seconds, else the summary's `hrTimeInZone_*`) and is omitted otherwise.
  - The HR chart in the profiles section draws faint horizontal bands for the run's zones behind the line, and the HR line takes the colour of the zone it is in, changing exactly at each boundary (a darker shade in light, lighter in dark); with no zones it is the accent colour. The bpm ranges (legend, tooltip, bands) are the run's own zones; the ⓘ says so.
- **Going in:** a card for the run's local day (`local_started_at.to_date`) from one `WellnessDay` lookup: resting HR with its 7-day average, last night's HRV with status and baseline band, last night's sleep (duration, score), Body Battery at wake. Nil values are left out, an empty marker row counts as nothing, and with nothing left the card is omitted.
- Layout: the two cards share a row at `lg` (zones two thirds, Going in one third), stack below, and either alone spans the full width; their tiles wrap and stretch, so nothing leaves an empty cell.

**Wellness page (`/wellness`)**

- A shared window: the Pace Trends presets (default the last year) and a brush on a compact daily resting HR timeline; `from` and `to` in the URL. Every chart follows it. Hovering any chart draws a vertical line at that day on all of them. Each chart overlay is one Tab stop: Left and Right step the cursor by a day, Home and End jump to the window's ends, Escape clears it; the tooltip anchors to the cursor line.
- Charts, one card each, shown only when their data exists:
  - **Resting HR:** daily dots with the 7-day average line (§5).
  - **HRV:** the nightly average as a thin line, one dot per night coloured by Garmin's status (balanced accent, unbalanced amber, low and poor red, else muted), over the baseline band.
  - **Sleep:** one bar per night stacked by stage (deep, light, REM; the bar is the time asleep, awake time is in the tooltip) with Garmin's sleep score as a line on a right-hand 0 to 100 axis. A night without stages is one unstacked bar. A dashed line on the hours axis is Garmin's sleep need for the night (`raw["sleep"]["sleepNeed"]["actual"]` in minutes, read in SQL and sent as seconds, from 2024; a missing night is a gap, and the y domain includes it). A night belongs to its wake-up date. The tooltip adds the need, average heart rate and stress during sleep.
  - **Bedtime and wake time:** one thin bar per night from when Garmin says you fell asleep to when you woke, so the window includes the awake time within it (`sleepStartTimestampLocal` and `sleepEndTimestampLocal`, local wall-clock epoch ms, read in SQL as seconds from the wake date's midnight, so the browser handles no time zones). The y axis is clock time with the evening before at the top (domain from roughly the 1st-percentile bedtime to the 99th-percentile wake time, so a few unusually early or late nights run off the edge; ticks every 2 hours as `HH:MM`). An amber line is the 7-day average time of falling asleep and a green line the 7-day average time of waking (§5 rule: at least 4 values in the window). A night missing either time, or whose wake day isn't its row date, is a gap. The tooltip has Fell asleep, Woke (both with their real times, even when off the axis) and Sleep window, which comes from the GMT timestamps so DST nights are right. Shown only when both series exist.
  - **Body Battery:** a bar per day from its low to its high, with the value at wake as an amber mark.
  - **Stress:** the daily average as dots and a thin line.
  - **Weight:** measurements as dots with the 30-day centred moving average as the line (§5).
  - **Top-run VDOT:** the Pace Trends top-run line.
  - **Time in HR zones per week:** stacked bars (zones 1 to 5, hours, Monday weeks) summed in SQL from each run's stored zone seconds (estimated runs included), in the `--hr-zone-N` colours.
- Missing days are gaps, not zeros: days are sent densely (one entry per day from the first to the last day with a value, `null` where none), so lines break at gaps. Before a device recorded a metric, its chart simply starts later.
- `Wellness::Trends` builds one columnar JSON payload from five queries. With no wellness data the page shows an empty state.

### 4.7 Gear

Strava gear, read-only (§2). Modelled on the Gear page of the owner's Dreeve instance, for running shoes only.

- **Source:** each Strava run carries a `gear_id` (null when none is set); each gear has a name, brand, model and description (§6.5). Gear reaches our runs through the `strava_id` link, so only Strava-linked runs have gear information.
- **Gear page (`/gear`):**
  - **Active gear table:** one row per gear, most used first: name (brand and model under it), runs, distance, moving time, distance in the last 12 months, last used. Retired gear sits under a collapsed "Retired (n)" toggle. Totals are summed from our runs, not Strava's gear totals.
  - **No gear set:** an amber row for linked runs with no gear (count, distance, last run), linking to `/runs?gear=none`.
  - **Gear no longer on Strava:** gear whose `GET /gear/{id}` returned 404 with no stored payload is listed by its Strava id in the active table, with the runs and distance we still carry for it. A gear fetched before keeps its stored details when a later fetch 404s; only `synced_at` moves.
  - **Distance per month per gear** (stacked bars) and **distance over time per gear** (cumulative lines): a toggle button per gear turns it on or off; retired gear starts off. Both x axes cover only the visible gear, from the first month any of it was used to the last (lines start one month earlier, at zero), and redraw on every toggle; with no gear visible the full range stays. Up to 18 months the bars are labelled by month, longer by year.
  - **Refresh from Strava:** starts a full gear scan (about 15 requests).
  - Until the first full scan has finished, the page says so (instead of listing every run as without gear); if it keeps failing, it says the first scan failed and points to Refresh. Without gear access it shows the Reconnect hint.
- **Fixing runs with no gear:** `/runs?gear=none` lists those runs with a **Suggested** column (the gear used most in the 14 days either side) and an Open in Strava button per row. You set the gear on Strava; the run leaves the list after the next hourly recent scan (last 30 days) or a manual refresh.
- **Runs list and run page:** the gear tag in the Tags & gear cell and the `gear` filter (one gear, or `none`); the run header's gear line. Runs without a Strava link show neither, since their gear is unknown rather than unset.

### 4.8 Pro Map

A full-page view at `/runs/:id/map`, opened from the run page ("Open Pro Map"). Runs without a GPS route (or without the public Mapbox token) have no button, and the URL redirects to the run page.

- **Route colouring:** the route is split into segments coloured by the selected metric (a button group; metrics a run lacks are left out):
  - **Pace:** the 37 pace zones (§5), fixed across all runs. Needs the run's splits, so rebuilt-distance runs lack it.
  - **HR:** the run's HR zones, `--hr-zone-N`.
  - **Grade:** −10% to +10% in 2% buckets (the outer ones take anything beyond), from altitude over 200 m windows.
  - **Cadence:** under 150, then 10 spm ranges up to 190+.
  - Map tiles follow the theme, with the terrain layers of §4.5.
- **Distribution bars** under the map, one per bucket of the current metric (time share), with Smashrun's click cycle: 1× selects only that bucket, 2× that bucket and above, 3× that bucket and below, 4× resets. The selection stays bright on the map, the rest dims. The legend shows distance, duration, average pace, HR and cadence for the selection.
- **Fastest segments:** 250 m, 400 m, 1 km, 5 km, 10 km, half marathon and marathon, up to the run's length, each with time, pace and VDOT (none under 400 m). Computed on the fly from the stored track (`Track::Efforts`), not stored; the track keeps at most 2,000 points, so on long runs a segment's start, end and time are approximate (the ⓘ says so). Clicking one isolates it on the map and updates the stats; again clears it.
- **Splits** per km, showing the current metric's column (pace, HR, elevation or cadence). Clicking a split isolates it.
- **Change-in-pace graph** under the map (pace per 100 m). Hovering a metric button overlays that metric on a secondary axis; hovering the graph moves a marker on the map through the shared run cursor.

### 4.9 Training Bands

- **Precomputed per run:** `activities.bands` (JSON) holds seconds per pace zone (the 37 zones of §5), per HR zone (1 to 5, each run's own zones) and per grade bucket, computed by `Track::Bands` from the stored track (`tracks.data`), never from the originals. `process_original` sets it; `bin/rails activities:bands` backfills it from stored tracks in seconds. A run with a rebuilt distance (§5) has no bands.
- **How a run is cut:** the track is walked in windows that close at 100 m or 30 s, whichever comes first, so stopped time lands in the walk zone. A window's speed gives its pace zone; its mean HR (missing HR skipped; a bpm under zone 1's floor counts as zone 1) gives the HR zone with the run's own boundaries; its altitude change over its distance gives the grade bucket (windows under 20 m, or without altitude, are left out). Grade buckets: below −8%, −8 to −4, −4 to −1, −1 to +1, +1 to +4, +4 to +8, above +8%.
- **Page (`/training_bands`):** one stacked area chart of time per week (Monday weeks, `local_started_at`) across all history.
  - **Category** (button group): Pace, Heart rate, Grade; Heart rate only when some run has HR bands.
  - **View** (button group): Absolute (hours per week) or % (each band's share of the week's total running, so hiding bands leaves the shown share rather than rescaling to 100%).
  - **Band filters:** one toggle button per group, all on by default, with a swatch of the group's colours. Pace groups: Walk (under 5.5 km/h), Easy (slower than 6:00 /km), Steady (6:00 to 5:00), Tempo (5:00 to 4:17), Fast (faster than 4:17), fixed boundaries (`TrainingBands::PACE_GROUPS`). HR groups are the five zones, grade groups the seven buckets. Filters are kept per category for the visit, not in the URL.
  - **Window:** the Pace Trends presets (default All time) and a brush on a timeline of weekly hours; `from`, `to`, `category` and `view` are URL params, updated in place.
  - **Colours:** pace bands `--pace-zone-N`, HR bands `--hr-zone-N`, grade `--grade-0` to `--grade-6` (blue for descents through grey to orange and red for climbs).
  - **Tooltip:** hovering a week (or Left, Right, Home, End, Escape on the chart's Tab stop) lists each shown group's time and share of the week, then the total.
  - **ⓘ:** explains the groups and says each run uses its own HR zones (estimated before the watch recorded them).
- The payload is columnar: one dense array of weekly seconds per band (bands with no time left out), summed in Ruby from one query.

### 4.10 Progress Towards Goal

**Goals (`/goals`)**

- Monthly and yearly distance goals, stored locally (`resources :goals`): an index table (goal, target, done, %, status), new and edit forms (period, any date in the month or year, distance in km) and a show page. A goal is unique per period and start; the start snaps to the first day of the month or year. Distance must be above 0 and under 100,000 km. Delete is a button with a confirm on the show page.
- The show page has four tiles (done and %, ahead or behind the direct path, needed per day with the days left, the recent average) above the chart.
- **Yearly tile** (Overview, beside Kilometers run): distance done of the goal, a progress bar with a tick at the direct path, percent, ahead or behind and the required km per day; links to the goal. All time shows the current year's goal, a year view that year's (a past year is final, no requirement). The current year without a goal shows a quiet "Set a yearly goal" tile whatever other goals exist. A past or future year without a goal, and every month view, have no tile: Kilometers run then spans the full row at `lg`, so the grid has no gaps.
- **Monthly widget** (Overview row above the tiles): all time shows the current month's goal, a month view that month's; year views have none. The subtle "Set a monthly goal" link appears only while neither the current month nor the current year has a goal; a past month without a goal shows nothing. The yearly goal is never also in this row.

**Chart**

- An accent line shows cumulative distance by day. A grey dotted line shows the direct path (goal × day ÷ days). The y axis reaches the goal or a larger total.
- Hovering a past day shows distance, the direct path, ahead or behind and that day's run total. A future day shows the average per day needed if you start that day (§5). Today shows both. The cursor is a Tab stop with Left, Right, Home, End, Enter (opens the run) and Escape.
- When behind (goal not reached, period not over), a red dashed catch-up line runs from today's total to the goal, its opacity the required daily distance relative to the recent daily average (§5).
- Bars along the x-axis mark run days, their height the daily total; clicking one opens its longest run. Days bucket by `local_started_at` date.

## 5. Metrics and formulas

All metric math lives in Ruby and is unit-tested. The only JS math is interactive recomputation (regression, brush stats, cycling, hover selection), tested with `node --test`.

- **Run eligibility:** an activity counts if its type is a running subtype and its distance is ≥ 0.1 km. Treadmill, indoor and virtual runs count but are flagged.
- **Time basis:** `timer_s` is Garmin's `duration`, which excludes manual pauses; it drives pace, VDOT and PRs. `elapsed_s` and `moving_s` are also stored. A run *has pauses* when `elapsed_s − timer_s ≥ 60`.
- **Local time:** all day bucketing (streaks, weekdays, AM/PM, calendars) uses `local_started_at` (Garmin's `startTimeLocal`, stored as-is). `started_at` is true UTC.
- **VDOT** (Daniels–Gilbert), v = m/min, t = minutes:
  - VO2 = −4.60 + 0.182258·v + 0.000104·v²
  - %max = 0.8 + 0.1894393·e^(−0.012778·t) + 0.2989558·e^(−0.1932605·t)
  - VDOT = VO2 / %max; `nil` for runs under 400 m or a time ≤ 0.
  - The ⓘ text (run page performance index, Pace Trends title, runs table header): "VDOT is Jack Daniels' estimate of the VO2max a run implies, on the same scale as your watch's VO2max. It puts every distance on one scale, and one point is worth about 2% of race time. Easy runs score lower because they aren't all-out." followed by example times for VDOT 45 and 50, computed from `Vdot.time_for` (VDOT 45 ≈ 5K 21:49, 10K 45:13, half 1:40:14, marathon 3:28:16; VDOT 50 ≈ 19:56, 41:20, 1:31:31, 3:10:40).
  - **Why VDOT and not SPI:** SPI is Smashrun's 1 to 1000 score on a 1974 world-record curve. Predicting each of the owner's 10K, half and marathon PRs from the other two, VDOT was off by 2.0% on average and SPI by 4.8%.
- **Predictions and estimated finish:** time at distance D for a VDOT inverts the formula numerically (`Vdot.time_for`, bisection). `Vdot.time_table(distance)` ships a lookup table per distance (VDOT 10 to 90, finer steps at low values) that the browser interpolates linearly. The run page's estimated finish uses `Vdot.time_for` at 5K (5,000 m), 10K (10,000 m), Half (21,097.5 m), Marathon (42,195 m).
- **Pace zones:** 37 fixed zones (`PaceZones`), shared by the performance index, the Pro Map and Training Bands. Zone 0 is "walk": below 5.5 km/h. Zones 1 to 35 are each 0.5 km/h wide, from 5.5 up to 23.0 km/h, labelled with the pace at the zone's upper edge, seconds rounded down (zone 1 "10:00", zone 2 "9:13", zone 35 "2:36"). Zone 36 is "zoom": 23.0 km/h and up. The colour ramp runs from dark red (walk) through orange, yellow, green and blue to white, as CSS variables so light and dark differ at the ends.
- **Performance zone:** the pace at which the run's VDOT would run a 5K (`Vdot.time_for(5000, vdot)`, as km/h), looked up in the pace zones.
- **Performance strip range:** take the performance zone of every run with a VDOT; the range runs from the zone of the 25th-percentile VDOT (index `floor((n − 1) × 0.25)` in the sorted list) minus 1, to the zone of the best VDOT plus 1, clamped to 0 to 36, then widened to include this run's zone. Each zone keeps its global colour. A history of one run gives three zones around it.
- **Hill difficulty:** an integer 1 to 5, nil without elevation gain. 1 when the run climbs under 1.5 m per km, otherwise 1 plus one step per 8 m per km (rounded up), capped at 5. Smashrun's formula is not public; this was fitted to its public ratings.
- **Rank histograms:** the cohort is all runs (distance) or runs within ±10% of this run's distance (pace). Bins are equal-width over the 2nd to 98th percentile, at most 12; both edges trim `round(0.02 × (n − 1))` runs, so trimming starts at 26 runs; values beyond fold into the first or last bin, labelled open-ended only when something folded in. Smaller cohorts, and cohorts where every value is equal, use the full range. Ranks use the true values.
- **PRs (Smashrun rule):** for benchmark D, qualifying runs have D ≤ distance < D + 1 km. PR time = `timer_s × D / distance`. Bucket count = number of qualifying runs. A PR is "official" when the Garmin event type is `race`.
- **Streak and break:** a streak is maximal consecutive local dates with ≥ 1 run. A break is maximal consecutive dates without a run, between the first run and the end of the period.
- **Trailing N days:** for each date, the sum of distance over `[date − N + 1, date]`.
- **Top runs:** a run is a top run if its VDOT ranks ≤ 3 among runs in `[date − 29 days, date]`. Smashrun's FAQ says "3 best per month" while its blog says "rolling 30-day"; we use the rolling window.
- **Regression:** OLS of VDOT against time (days) over the top runs in the window. The band is ±1 SD of the residuals. Weekly change = slope × 7.
- **Pace axes:** linear in speed, labelled as pace (Smashrun's 4:17 / 5:00 / 6:00 / 7:30 / 10:00 / 15:00 / 30:00).
- **Pace variability:** distance covered in consecutive complete 10 s windows while the timer is running (stops count, the final partial window doesn't, at least two windows needed), then mean absolute deviation ÷ mean, as a %. Windows use linear interpolation between samples, so sparse recordings can hide changes. Stored on the run; the wheel is drawn separately from the 100 m bars.
- **Runs in the prior 90 days:** the window is `[local midnight of the run's day − 90 days, the run's start)`. The mean is over previous runs that have the metric. Brush readouts: share = brushed ÷ previous runs; hours = Σ `timer_s`; distance = Σ `distance_m`; count. A brush selects values inside its range, edges included.
- **Elevation change bins:** computed from the full-resolution recording before the 2,000-point downsampling. Per 100 m bin, gain and loss are summed with a 1 m hysteresis; the turning point carries across bin and km boundaries, and a change is attributed to the segment where it passes the threshold, split by distance when it spans bins. A missing altitude resets the turning point and marks its bins as missing. The per-km splits' gain and loss are sums of the same bins. Totals can differ from Garmin's summary.
- **Tracks:**
  - Garmin originals are untrimmed (Garmin applies trims only to the summary). FIT records before `started_at` (−2 s) are dropped, then records whose timer time exceeds `timer_s` (+2 s). Clipping to `elapsed_s` is wrong: it can be shorter than the file's wall-clock span on runs with long pauses.
  - TCX isn't clipped (the parser keeps no per-row timestamps). Pauses are removed per lap: the lap's excess (the time the lap adds to `t`, namely its own gaps plus the gap into its first trackpoint unless over 10 s, minus `TotalTimeSeconds`) is taken out of stall gaps (over 10 s, distance advancing under 0.5 m/s), largest first. Garmin's `timer_s` for these imports equals the sum of the laps' `TotalTimeSeconds`.
  - `t` is timer seconds with pauses removed, `d` cumulative metres, cadence steps/min for both legs.
  - If the distance series is missing or more than 10% off `distance_m`, `d` is rebuilt at constant pace, and `splits`, `pace_variability` and `bands` stay nil; the run page omits the speed chart.
  - Zero cadence and zero heart rate are missing values for every format (recordings carry cadence 0 while stopped).
  - Smashrun's no-GPS marker (`latitude` = `longitude` = −1.0) becomes a missing position.
  - Smashrun `clock` includes stopped time: the excess of `t` over the row's `timer_s` is removed from stopped intervals (distance advancing under 0.5 m/s), largest first and never more than the excess, with final `d` unchanged. `timer_s` is the budget, not the detail's own `duration`.
  - `Track#bars(100)` gives the 100 m bars of the speed chart and the wheel; `Track#route` and `Track#route_distances` are parallel lists for the map and its cursor marker.
- **Notables:** computed on the fly by `Notables.for(activity, runs)`, no stored column, as of the run's date. Longest run; fastest run for a similar distance (±10%); most elevation gain; hottest or coldest run; earliest or latest start; each shows the largest window that holds (1, 3, 6, 12 months, "ever"). Windowless: during sunrise or sunset (start or end within ±30 min, from Open-Meteo's daily times), full or new moon, first run at a new Garmin location name, extends the longest streak, first run of the year, lifetime distance milestones (every 1,000 km).
- **Food equivalents:** a static list of foods with kcal (`Food::ITEMS`). `Food.for(calories)` picks the food whose multiple (1 to 12) best matches the run's calories.
- **HR zones:** time in zone is the stored `seconds` (Garmin's `time_in_hr_zone` from the FIT; estimated runs: each track interval goes to the zone of its end sample, below zone 1 and missing HR skipped). `HrZones#range(zone)` is the bpm range.
- **7-day average:** the mean of the values in the 7 calendar days ending on the day, shown only when that window holds at least 4 values and the day has a value of its own; missing days are skipped, not counted as zero.
- **Weight trend:** a 30-day centred moving average of the daily weight (the day's latest weigh-in). Unlike the 7-day average it bridges gaps between weigh-ins (linear interpolation between neighbouring trend values) but draws nothing before the first or after the last.
- **Gear stats:** distance = Σ `distance_m`, time = Σ `timer_s` of the runs with that gear; "last 12 months" = the 365 days ending on the latest run's date; last used = the latest `local_started_at`. Suggested gear = the gear on most runs in the 14 days either side.
- **Goal progress:**
  - A goal spans the days of its month or year; day i's total is the sum of that local date's runs; cumulative distance is the running sum through today (or the period's end).
  - The direct path through day i is goal × (i + 1) ÷ days. Ahead or behind = done − the path through today, but until today has a run the path stops at yesterday, so a goal isn't red from the first hour of the day. A finished period shows where you finished and no required rate.
  - Required per day = remaining ÷ days left, where days left counts today. For a future day d it is remaining ÷ (days − d), as if nothing more is run before d. Nil once the period is over, 0 once the goal is reached.
  - Behind: the period is running, the goal isn't reached and done is below the path.
  - **Recent daily average:** all runs in the 28 days ending today ÷ 28 (`Goal::Progress::RECENT_DAYS`). Catch-up ratio = required ÷ recent average (none when the average is 0). Line opacity is 0.35 up to a ratio of 1, rising linearly to 1 at 3 or more, and 1 without a recent average.

## 6. Data sources and sync

### 6.1 Garmin Connect Personal API

- **Base URL:** `https://personal.connectapi.garmin.com`.
- **Auth:** `POST /personalapitoken-service/personal-api/personal-api-key/token` with `Authorization: ApiKey <key>` (`GARMIN_API_TOKEN` in `.env`) returns a bearer JWT as `text/plain`, valid 24 h. There is no refresh token; exchange the key again. The token is cached in `Rails.cache` until `exp − 1 h`. On a 401 it re-exchanges once; if the exchange fails, the key has expired (keys last 30, 90, 180 or 365 days) and the rotation banner shows.
- **Client:** a thin `Net::HTTP` wrapper in `app/lib/garmin/client.rb`; no gem.
- **Throttling:** at most 1 request/s; exponential backoff on 429 or 5xx and transient network errors (up to 5 tries). No rate-limit headers are sent. Activity search page size is 100 (`limit=250` returns HTTP 500). All writes are idempotent upserts, so restarting is always safe.

| Endpoint | Used for |
|---|---|
| `GET /activitylist-service/activities/search/activities?activityType=running&start&limit` | Run summaries, newest first. Includes `trail_running`; treadmill runs are `treadmill_running`. Don't drop the filter: unfiltered pages mix in other sports. |
| `GET /userprofile-service/userprofile/settings` | Profile settings |
| `GET /download-service/files/activity/{id}` | Original file as a ZIP with one `.fit` (watch runs) or one `.tcx` (2017 bulk imports). Untrimmed. |
| `GET /biometric-service/heartRateZones/v2` | Per sport `zone1Floor` to `zone5Floor`, `maxHeartRateUsed` (the bare path and `/all` are 404) |
| `GET /usersummary-service/usersummary/daily?calendarDate=` | One day: resting HR and its 7-day average, average stress, Body Battery high, low and at wake. A day without data is 200 with null fields. |
| `GET /hrv-service/hrv/daily/{from}/{to}` | `hrvSummaries` (`lastNightAvg`, `weeklyAvg`, `status`, `baseline`). Accepts 30 or 90 days in one request; no data is 204 with an empty body. |
| `GET /weight-service/weight/range/{start}/{end}?includeAll=true` | `dailyWeightSummaries`, weights in grams |
| `GET /sleep-service/sleep/dailySleepSummariesByDate?startDate&endDate` | One object per night under its wake-up `calendarDate` (31 days per request): stage seconds, `sleepScores.overall.value`, `avgHeartRate`, `avgSleepStress`. Empty before the first night: an empty array. |

Not used: the stress and Body Battery range endpoints and `/usersummary-service/v2/dailysummaries` (the daily summary has the same values, and v2 lacks the 7-day resting HR average and wake Body Battery; 365 days is HTTP 500). Not available (404): training readiness, training status, VO2max (`maxmet`), `dailySleepData`, and any path with a `{displayName}`. The Personal API has no time-series, laps or weather endpoints; its only split data is `splitSummaries` groups, with no recovery heart rate. `bin/rails garmin:probe` re-checks candidate endpoints read-only (statuses and JSON shapes, never values).

Summary field notes: `startTimeGMT` and `startTimeLocal` are `"YYYY-MM-DD HH:MM:SS"` strings without zone, both parsed as UTC; `averageHR`, `maxHR` and `calories` are floats; `eventType.typeKey` is `race` or `uncategorized`; `vO2MaxValue`, `locationName` and `fastestSplit_*` are often missing; "runs" under 100 m are skipped. Summaries carry `splitSummaries` and `hrTimeInZone_*` but no time series. The activity URL `https://connect.garmin.com/app/activity/:id` works.

### 6.2 Sync flow

- **Backfill:** page through the activity search newest to oldest until a page is empty, upserting by `(source, external_id)`. **Incremental:** page newest-first until a full page is all known IDs. **Full resync** (`activities:resync`): re-pages everything, picks up edits, and deletes local Garmin runs that no longer exist upstream.
- **Triggers:** the hourly `garmin_sync` recurring task (`config/recurring.yml`, production) and the **Sync now** button, both `Activity::SyncJob` → `Activity.sync_now` (the button through `Activity.sync_later`). `bin/dev` syncs only on the button. After a successful sync the Strava link job queues a recent pass (§6.5).
- **Live status:** every page subscribes to the `garmin_sync` stream. Sync now answers a Turbo request with a `turbo_stream` that shows "Syncing…" at once (the redirect stays for plain requests); the job then broadcasts the status on start and end, and a page refresh when runs changed or a sync's error changed. The Strava link job broadcasts a refresh when it linked a run or changed a gear, since those land after the sync. "Synced N ago" is a `<time>` that ticks every 30 s client-side with Rails' `time_ago_in_words` wording (the server render is the fallback), and the page refreshes when the stream reconnects after a drop (the `connected` attribute of `turbo-cable-stream-source`), because cable doesn't replay missed broadcasts, unless a form field is on the page, so typed input is never lost.
- **Originals:**
  - `bin/rails activities:download` is the one-time backfill of originals, bounded by the 1 request/s throttle (about 45 minutes for 2,500 runs); parsing is a few milliseconds a file.
  - The sync downloads the original of every run it pages through that has none, processes a run that has an original but no track, and reprocesses a run whose `started_at`, `timer_s` or `distance_m` changed (picks up trims). A failure for one run is logged and skipped; the next sync retries it. It refreshes `sync_started_at` after each run, so a long sync keeps counting as running.
  - `bin/rails activities:reprocess` rebuilds all derived data from stored originals.
- **Weather:** each sync fetches weather for every run up to 60 days old that has none (§6.4). `bin/rails weather:fetch` is the full backfill.
- **Wellness:** a separate hourly job (`wellness_sync`, `Wellness::SyncJob` → `Wellness::Sync#refresh`, at minute 30), so a wellness failure never blocks run syncing. It refreshes today and the last 3 days (Garmin fills in late data) plus the HR zones, and sets `profiles.wellness_synced_at`. `bin/rails wellness:backfill` (`DAYS=n` limits it, `ONLY=sleep,hrv` limits the metrics) is the one-time backfill from the first run onward: 1 request/s, newest first, in 30-day chunks (the daily summary is one request per day), idempotent and resumable. Stored summary days are skipped, and so are empty-marker days once 7 days past their date (a younger marker, written by the hourly refresh before the watch synced, is fetched again). A source stops after 6 consecutive chunks with no data. It prints counts only.

### 6.3 Strava gap fill

`bin/rails strava:fetch` uses the connected Strava account (§6.5), pages through `/athlete/activities` and applies the cutoff below. `start_date` is UTC and `start_date_local` is wall-clock time with a `Z` suffix, so both are parsed as UTC. `average_cadence` is per leg; `workout_type` 1 is a race; `trainer: true` is a treadmill run; summaries have no calories. The archive import is a fallback: request the archive from Strava, unzip it and run `bin/rails strava:import[/path/to/archive]` (reads `activities.csv`, rows whose type matches `/run/i`).

1. **Cutoff:** Garmin is authoritative from its first run on. Rows that start later than 10 minutes before the first Garmin run are skipped, and the tasks refuse to run without Garmin runs. Every Strava-only "run" inside Garmin's history was a hike Garmin recorded as hiking or a duplicate. Known limit: a phone-only run recorded after Garmin started won't import.
2. Imported runs get `source: "strava"` and link out to Strava.
3. Tracks come from Smashrun (§6.5), not Strava streams. The walk (Strava `214619496`) was deleted; don't re-import it.

### 6.4 Weather (Open-Meteo)

- Hourly temperature, humidity, wind and precipitation at the run's local midpoint hour, plus daily sunrise and sunset, `timezone=auto`; coordinates rounded to 0.01°; cached on the activity (`weather`).
- Runs whose midpoint is older than `Activity::Weather::ARCHIVE_LAG` (5 days) use the archive API; newer runs use the forecast API (`start_date`/`end_date` serve the recent past), so yesterday's run has weather. A stored value is never refetched. When either API returns nulls, `weather` stays nil and a later sync retries.
- Treadmill and indoor runs, and runs without start coordinates, get no weather.

### 6.5 Smashrun, Strava connection and gear

**Smashrun** supplies tracks for the runs before Garmin, and the one run that exists only there (3 Mar 2015, 8.00 km, treadmill).

- **Login:** `POST https://secure.smashrun.com/services/apiauth-jsonservice.asmx/ConnectUserLogin` with `SMASHRUN_USERNAME` and `SMASHRUN_PASSWORD` returns a 12-week token. `info.message` reads "An unexpected error occurred on the server" even on success, so check `isFailed` and that a token is present. The token is held only in memory.
- **API:** `https://api.smashrun.com/v1`, bearer token, 250 requests per hour, so the client spaces calls 15 s apart. `GET /my/activities` returns all summaries in one response (`page` and `count` ignored): `activityId`, `startDateTimeLocal`, `distance` (km), `duration` (s), `isRace`/`isTreadmill`, `calories`, HR and cadence stats, elevation, start coordinates. `GET /my/activities/{id}` adds series-major `recordingKeys`/`recordingValues` (`distance` km, `latitude`, `longitude`, `elevation`, `heartRate`, `cadence` per leg, `clock` in s including pauses), `pauseIndexes`, `laps`.
- **`bin/rails smashrun:fetch`:** keeps summaries that start more than 10 min before the first Garmin run (the cutoff compares UTC); matches each to the nearest activity by local wall clock (`local_started_at` against `startDateTimeLocal` with the offset ignored) within ±10 min, because Smashrun's UTC offset is wrong on some runs; a match gets nil `calories` filled and `race` ORed; an unmatched run is created with `source: "smashrun"` (exactly one is expected); every matched or created run gets its details stored as `smashrun-<id>.json.gz` and processed. Resumable; prints a report.
- Known data: Smashrun `6093331` and `5850866` have null recordings, so those two Strava runs have no track. The Smashrun-only run's distance series is unusable (0.18 km against 8.00 km), so it uses the summary distance. The 2017 iSmoothRun treadmill TCX imports have sparse trackpoints and inconsistent Garmin summaries (for example `1757716207`: track `t` 2,501 s against `timer_s` 2,830). Two Garmin runs have rebuilt distances: `3843370908` (summary edited on Garmin to 3,000 m more than the file holds) and `8547425833` (records end at 10,998 m, summary says 17,202 m).

**Strava connection**

- The nav's Connect Strava button (shown only while disconnected) starts Strava's OAuth with a session `state` (scope `activity:read_all,profile:read_all`). The callback is `GET /strava/callback` on whichever host serves the app. It checks the state and that the grant includes activity access (otherwise a fixed alert, nothing stored), stores the access token, refresh token and expiry on `Profile` (both encrypted with Active Record encryption) and `profiles.strava_scope`, and queues a full link. The button's form has `data-turbo=false`, because Turbo's fetch can't follow the cross-origin redirect.
- A grant without `profile:read_all` leaves the nav on **Reconnect Strava** and gear features wait (not an error).
- `Strava::Client` refreshes when the token expires within 5 minutes and saves the rotated refresh token. The refresh is made outside any transaction; if Strava rejects it but the stored refresh token is no longer the one sent, another process rotated it, so the new token is used. A 401 on activities, or a 400/401 on refresh, clears the connection so the button shows again. Requests use 10 s open and read timeouts and are not retried. Limits: 100 requests per 15 minutes, 1,000 per day.
- **Links:** `activities.strava_id` matches the run whose `started_at` is within ±10 minutes of the Strava run's start, nearest first, never overwritten or reused. Connect queues a full scan (about 15 requests at 200 per page); each Garmin sync queues a recent pass that asks only for activities after the oldest unlinked run of the last 14 days (no request when none). Strava's `external_id` (upload file name, or `garmin_push_N`) is not used for matching.

**Gear**

- The same scans read each activity's `gear_id` (null = no gear) into `activities.strava_gear_id` for every `strava_id`-linked run, including the pre-Garmin rows. Each distinct `gear_id` gets one `GET /gear/{id}` (refreshed weekly) plus `GET /athlete` for the shoe list; the raw payload is stored in `gears.summary`, and `retired` is read from it (false unless the payload says true).
- Passes: a full scan on connect and on Refresh from Strava; an hourly recent pass over the last 30 days (one request), in the same job as the link pass so only one job refreshes the token. `profiles.strava_gear_synced_at` is set when a full pass finishes; until then the Gear page says the first scan is pending, the hourly pass is the full one (unless it has failed `STRAVA_GEAR_ATTEMPTS` (2) times, see below), and no run shows a gear tag or an amber No gear.
- Failed full passes (any Strava error except a disconnect, and network timeouts) count in `profiles.strava_gear_attempts`; after 2 the hourly pass goes back to the recent one (a gear that always fails would otherwise cost about 500 requests a day) and the Gear page says the first scan failed. A successful full pass or a reconnect resets the count. A Strava error in the gear step of a link job is logged by class and doesn't fail the job. A run's gear changes on the next hourly scan only within 30 days; older runs change on Refresh.
- Gear is read-only: no write calls to Strava.

## 7. Data model (SQLite)

### `activities`

| Column | Notes |
|---|---|
| `source` | `garmin`, `strava` or `smashrun`. Unique with `external_id`. |
| `external_id` | Garmin, Strava or Smashrun activity ID. |
| `strava_id` | Nullable, indexed. The Strava activity behind Open in Strava: from `external_id` for Strava-sourced runs, by the link job for the others (§6.5). |
| `strava_gear_id` | String, nullable, indexed. The Strava gear ID as read; matched to `gears.strava_id` by value, so activities can be read before their gear row exists. |
| `started_at` | UTC |
| `local_started_at` | Local wall-clock time; used for all day bucketing. |
| `name`, `activity_type` | Type is a Garmin type key: `running`, `trail_running`, `treadmill_running`, … |
| `indoor` | true for treadmill, indoor and virtual |
| `race` | true when the event type is `race` |
| `distance_m`, `timer_s`, `moving_s`, `elapsed_s` | |
| `elevation_gain_m`, `elevation_loss_m` | |
| `avg_hr`, `max_hr`, `avg_cadence`, `max_cadence`, `calories`, `vo2max` | Nullable; older runs lack some. `vo2max` stays empty (the Personal API summaries have none). |
| `start_lat`, `start_lng`, `location_name` | |
| `vdot` | Computed on save |
| `summary` | JSON: the raw Garmin summary or Strava row, so fields can be re-derived without re-fetching (HR zone times, training effect and load, Body Battery change, running dynamics, `pr`, `avgGradeAdjustedSpeed` are read from here). |
| `splits` | JSON, per km; nil for rebuilt distances |
| `pace_variability` | Float; nil for rebuilt distances |
| `weather` | JSON: temperature, humidity, wind, precipitation, code, sunrise, sunset |
| `hr_zones` | JSON: `floors`, `max_hr`, `seconds`, `source` (§4.6) |
| `bands` | JSON `{"pace": [37 seconds], "hr": [5], "grade": [7]}` of whole seconds per pace zone, HR zone (zone 1 first) and grade bucket (steepest descent first), from the stored track (§4.9). An array totalling 0 is nil; the column is nil for rebuilt distances and runs without a track. |

`has_one_attached :original` (Active Storage, local disk): the Garmin ZIP as downloaded, or the gzipped Smashrun detail `smashrun-<id>.json.gz`. Index on `local_started_at`. Aggregations load the period's runs into Ruby (about 2,900 rows); add caching only if measurements show a need. There is no `notables` column.

### Other tables

- `tracks`: `activity_id` (unique), `data` (JSON of columnar arrays `t, d, lat, lng, alt, hr, cad`, downsampled to ≤ 2,000 points; series without data omitted) and `chart_metrics` (nullable JSON: `elevation`, the 100 m gain/loss bins, and `steps` for workout runs, `[{type, from, to, time}]` in metres and seconds; nil for rebuilt distances). A separate table keeps activity loading lean.
- `wellness_days`: `date` (unique), `resting_hr`, `resting_hr_avg_7d`, `hrv_last_night`, `hrv_weekly_avg`, `hrv_baseline_low`, `hrv_baseline_high`, `hrv_status`, `body_battery_high`, `body_battery_low`, `body_battery_wake`, `stress_avg`, `weight_kg` (the day's latest weigh-in, from grams), the night that ended that morning (`sleep_s`, `sleep_deep_s`, `sleep_light_s`, `sleep_rem_s`, `sleep_awake_s`, `sleep_score`, `sleep_hr_avg`, `sleep_stress_avg`), and `raw` (JSON keyed `summary`, `hrv`, `weight`, `sleep`: the day's payload per endpoint). A day Garmin answered with no summary data gets a row with null columns and `raw["summary"]` = `{}` as an empty marker, so the backfill doesn't ask again (a refresh does). Null fields never overwrite stored values. A `sleepTimeSeconds` of 0 is stored as missing, and all four stage values are dropped when deep, light and REM are all 0. The columns and `raw` are in `config.filter_parameters`, so SQL binds show `[FILTERED]` in logs.
- `gears`: `strava_id` (string, unique), `name`, `brand_name`, `model` (Strava's `model_name`, which Active Record reserves), `retired` (boolean, default false), `summary` (JSON, the raw Strava payload), `synced_at`.
- `goals`: `period` (`month` or `year`), `starts_on`, `distance_m` (float, entered in km); unique on `period` and `starts_on`.
- `profiles` (singleton, `Profile.instance`): `settings` (Garmin profile settings JSON), `hr_zones` (JSON, Garmin's current zones), `synced_at`, `sync_started_at`, `sync_error`, `wellness_synced_at`, the Strava connection (`strava_access_token`, `strava_refresh_token` encrypted, `strava_token_expires_at`, `strava_scope`) and gear sync state (`strava_gear_synced_at`, `strava_gear_attempts`, default 0).

## 8. Architecture and stack

- **Generator:** `rails new . --name=chartlek --css=tailwind --skip-kamal --skip-thruster --skip-docker --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-jbuilder --skip-system-test`: SQLite, Importmap, Propshaft, Hotwire, Solid Cache/Queue/Cable, RuboCop omakase, Brakeman, `bin/ci`.
- **Gems:** `dotenv` (Rails doesn't load `.env`), `factory_bot_rails` and `webmock` for tests, `rubyzip` (Garmin downloads are ZIPs), `csv` for the Strava import; Nokogiri (already bundled) parses TCX.
- **JS (Importmap only, no Node build):** d3 pinned with `bin/importmap pin`. Mapbox GL JS is the single-file UMD build vendored in `vendor/javascript` with its CSS (`app/assets/stylesheets/mapbox-gl.css`), pinned with `preload: false` and imported dynamically so only pages with a map load it; the multi-chunk ESM build breaks under Propshaft's digested paths.
- **Code organisation (Visualizer `STYLE.md`):** rich models with thin controllers; class-scoped concerns (`Activity::Performance`, `Activity::GarminSync`, `Activity::StravaImport`, `Activity::StravaLink`, …); POROs in `app/models` for aggregates (`Overview`, `PersonalRecords`, `PaceTrend`, `PrProgress`, `HrZones`, `PaceZones`, `TrainingBands`); integrations in `app/lib` (`Garmin::Client`, `Strava::Client`, `Smashrun::Client`, `OpenMeteo::Client`); jobs follow `_later`/`_now`; view constants for cards, type and controls live in `WidgetsHelper` and `ControlsHelper` (§9).
- **Routes** (REST resources only): `resource :overview` (with `:year`/`:month`), `resources :runs` (index, show) with nested `resource :map`, `resource :pace_trend`, `resource :pr_progress`, `resource :wellness`, `resource :training_bands`, `resources :gears` (index, at `/gear`), `resource :gear_sync` (`create` = Refresh from Strava), `resources :goals`, `resource :sync` (`create` = Sync now), `resource :theme` (`update`), `resource :strava_connection` and the OAuth callback.
- **Charts:** one Stimulus controller per chart type (kebab-case or snake_case files in `app/javascript/controllers`); the server renders chart data as JSON into Stimulus values, so there are no JSON endpoints. Shared helpers and the pure logic of each chart are in `app/javascript/helpers/`. Charts redraw on `ResizeObserver`. Theme comes from CSS variables (`--chart-accent`, `--chart-muted`, `--chart-grid`, …), so a light/dark switch needs no redraw; the variables, Tailwind's `dark:` variant and `color-scheme` all key off `<html data-theme>`.

### Deployment

- One Docker container (`docker compose up -d --build`, Dockerfile on `ruby:4.0.9-slim`, Puma without Thruster) on port 9295, served at `https://chartlek.rekar.eu` by Caddy on the Pi over Tailscale. On the LAN it speaks plain http, so `force_ssl` and `assume_ssl` are off. Rails honours the forwarded scheme and host from any sender, so the Strava OAuth callback is `https://chartlek.rekar.eu/strava/callback`; the tailnet range is a trusted proxy only so that `request.remote_ip` is the real client. `Rack::Deflater` (in `config/application.rb`) compresses every response, and assets are served `immutable`.
- The production primary database is the same `storage/development.sqlite3` that `bin/dev` uses (SQLite in WAL mode), so there is one dataset; cache, queue and cable have their own `storage/production_*.sqlite3`. `./storage` is mounted, and `.env` (from `.env.example`) supplies the Garmin, Strava, Smashrun and Mapbox settings plus `SECRET_KEY_BASE` and the three Active Record encryption keys; there is no credentials file. The entrypoint runs `db:prepare` only. A migration run by the container marks the shared primary's environment as `production`; `bin/rails db:environment:set RAILS_ENV=development` undoes that for dev's protected tasks.
- Solid Queue runs inside Puma and runs the hourly Garmin sync (§6.2) and wellness refresh. There is no auth: the machine is only reachable through the LAN and the tailnet (§10).
- Rebuild the container after code or migration changes.

## 9. Design

One design system, defined once in helpers (`WidgetsHelper` for cards and type, `ControlsHelper` for controls), so views never write these classes inline. Both are plain constants plus a few view helpers (`page_header`, `empty_state`, `chip`, `button_group`, `segment`, `toggle_button`, `action_button`).

- **Theme:** System, Light or Dark, rendered as `<html data-theme>`. Chart colours are always CSS variables, never `light-dark()`, because the map reads them with `getComputedStyle`.
- **Palette:** accent is a nod to Smashrun's "Team Yellow Green": lime/green (dark mode base `#6ACD12`, highlight `#9CFF44`, low `#254806`; deeper greens in light mode). Amber for highlighted runs, "this run", predictions and the linked-hover selection. Neutrals from Tailwind `zinc`. Pace zones use one shared ramp (§5), HR zones `--hr-zone-N`.
- **Layout:** `max-w-7xl`. Every page is a header row (`page_header`: title and its ⓘ on the left, actions on the right, wrapping), then period or window selectors as button groups (`mt-4`), then the content (`mt-6`), whose cards sit `gap-4` apart. A page or list with nothing to show uses one `empty_state`. Two columns on desktop, one on narrow screens. Nothing scrolls sideways at 360 px.
- **Cards:** one style (`CARD`; margins stay at the call site). A card's title row (`CARD_HEADER`) has the title (`CARD_TITLE`) and its ⓘ on the left and the chart's button group on the right, wrapping on narrow screens; the chart follows at `mt-3`. A metric switch shows its selection in the title text ("Distance per month").
- **Type:** the system UI font stack. Page title `text-2xl` semibold; card title semibold; tile label small, medium, muted (`TILE_LABEL`); tile value `text-4xl` semibold `tabular-nums` (`TILE_VALUE`), the lime accent (`ACCENT`) only on headline numbers; units and sub-lines small and muted (`TILE_UNIT`, `TILE_SUB`); hints `text-xs` muted (`HINT`: type and colour only, each call site sets its margin) and legends (`LEGEND`); muted text `MUTED`, text links `LINK`, empty values `PLACEHOLDER`. Tables use `TABLE`, `TABLE_HEAD`, `TABLE_BODY`, `TABLE_ROW`, `CELL` and `TABLE_LINK`; tags on a run or record are `chip`. Long explanations go in the ⓘ; a hint stays only to say how to use the chart.
- **Controls** (sharing height, radius, focus ring and disabled style):
  - **Button** (`action_button`, `BUTTON`): an outlined action or link.
  - **Button group** (`button_group` with `segment`): a single choice among options (metric, window, mode, distance, period; the theme switch is one with icon segments). `aria-pressed` buttons in one track, or links when the choice is a page; the selected segment has one accent look everywhere. It replaces every `<select>`.
  - **Toggle button** (`toggle_button`): an independent on/off filter, drawn like one selected segment.
  - **Icon button:** the ⓘ (`ControlsHelper::INFO`) and the theme switch's icon segments (`ICON_SEGMENT`).
  - **Focus ring:** one global `a`/`button` `:focus-visible` rule in `application.css` (2 px, the chart accent, 2 px offset); no control writes its own.
- **Tooltips:** the shared tooltip. Title-and-rows tooltips use `tooltipHtml` (a muted title, then label/value rows), everything escaped; distances to one decimal.
- **Motion:** 150 to 250 ms transitions on chart updates; the one longer motion is the dot glide in "Runs in the prior 90 days" (about 400 ms).
- **Accessibility:** keyboard-operable charts (§4.1), visible `:focus-visible` rings, labelled controls, text contrast in both themes.

## 10. Privacy and security

- **Data sensitivity:** the app stores GPS tracks (which reveal home and routines), heart-rate data and health data (HRV, weight, Body Battery, stress, sleep). It is your own data, kept on your machine. Health values are never logged or printed, and test fixtures are synthetic.
- **Network exposure:** the container (port 9295) and the dev server (0.0.0.0:3000) are reachable on the LAN, and chartlek.rekar.eu is served by Caddy on the Pi over Tailscale. There is no auth, so the tailnet and LAN are the boundary; chartlek.rekar.eu is confirmed tailnet-only. HTTP basic auth at Caddy would be optional hardening.
- **Secrets:** `.env` is git-ignored (`/.env*`, except the committed `.env.example`) and mode 600.
  - Smashrun credentials grant full access to the Smashrun account; never log them. The 12-week token is held only in memory.
  - The Garmin key gives read access to all your Garmin health data; filter it and the bearer token out of logs and error output. Rotate at `connect.garmin.com/app/settings/personalApiToken`, update `.env`, restart.
  - Strava tokens are stored encrypted on the profile (keys from the `ACTIVE_RECORD_ENCRYPTION_*` variables in `.env`; losing them makes the stored tokens unreadable, so Strava has to be connected again). Never log them or the OAuth `code`.
- **Storage:** `storage/` (SQLite databases, stored originals) is git-ignored. `storage/dumps/` holds raw API dumps and captures: never print it or copy it into `test/`; encrypt any backup.
- **Design references:** other people's public Smashrun pages are read only to see their layout. Nothing from them is stored, logged or used as test data.
- **Third parties:** Garmin (the source); Strava (gap fill, run links, gear; read-only); Smashrun (until it shuts down; receives your login once per fetch); Open-Meteo (rounded coordinates and dates); Mapbox (style, tile and font requests, which reveal which areas you view, plus the public token). Every `Map` sets `performanceMetricsCollection: false` (GL JS otherwise sends the user agent, screen size and GPU); the only events still sent to `events.mapbox.com` are `appUserTurnstile`, `style.load` and `map.load` (the one Mapbox bills on), carrying the SDK version, the style URL, a token-derived SKU token and an anonymous user ID GL keeps in `localStorage` (`mapbox.eventData*`). No analytics.
- **Terms:** Garmin's Personal API is for personal use only. Making this multi-user would mean handling other people's health and location data, needing Garmin's business developer program and real privacy and compliance work. Out of scope.

## 11. Testing and acceptance

**Test suite:** Minitest, FactoryBot, WebMock with the network disabled; view helpers are tested too. Fixtures are synthetic: made-up coordinates, names, IDs, heart rates and wellness values. Nothing downloaded from your accounts goes into `test/`. JS: `node --test test/javascript/*_test.mjs` covers the pure logic of each chart helper (regression, brush stats, formatters, `tooltipHtml` escaping, linked selection, rank histograms, pace variability, run cursor, elevation profile, estimated finish, Analyze Run, wellness, training bands, goal progress, Pro Map).

**Unit coverage that matters:** VDOT golden values and predictions; pace zones (boundaries at 5.5, 6.0 and 23.0 km/h, nil VDOT); PR bucketing and interpolation, streaks, trailing sums, weekly buckets, magic PR targets, top-run flagging; Garmin client (token caching, re-exchange on 401, expired key); sync (idempotent upsert, delete reconciliation); Strava cutoff, connection (state and scope checks, refresh and rotation, revoked connection), ±10 minute matching and gear sync (missing scope, gear without a row yet, null gear, `retired` absent, 401); Smashrun import; track parsers (FIT, including the decoder's edge cases: big-endian definitions, developer fields, invalid values, array fields only when declared, redefined local types, skipped messages, compressed timestamp headers, 12-byte headers, every truncation raising `Track::Error`, a record without a timestamp; TCX with two `<Track>`s, Smashrun JSON) and metrics (splits, variability, elevation bins, clipping, cadence doubling, the 2,000-point cap, `route` and `route_distances` staying aligned when a GPS fix is missing); weather, notables, food; hill difficulty; wellness parsers and sync (idempotent upserts, the 3-day refresh, chunking, missing metrics); HR zones and the default bands; gear stats and the "no gear" and "suggested gear" rules.

**Golden values:** Chartlek's values next to smashrun.com/miharekar (all time, km), as of 2026-10-25. Smashrun used its own processing and counts about 470 km of hikes that Garmin recorded as hiking. Streaks and breaks must match exactly; totals and PRs within ±0.1%. Recompute when an aggregation changes.

| Metric | Chartlek | Smashrun |
|---|---|---|
| Runs | 2,868 | 2,942 |
| Total distance | 32,974.3 km | ≈ 33,464 km |
| Average run length | 11.5 km | 11.4 km |
| Runs after noon | 67% | 66% |
| Average pace | 6:07 /km | 6:14 /km |
| Longest break | 110 days (30 Oct 2014 – 16 Feb 2015) | same |
| Longest streak | 111 days (21 Apr – 9 Aug 2020) | same |
| PR 5 km | 24:23 (12 Apr 2022) | same |
| PR 10 km | 42:44 (14 Oct 2019); bucket of 1,098 runs | 42:45; bucket of 1,104 |
| PR half marathon | 1:37:34 (24 Mar 2019, race) | 1:37:30 |
| PR marathon | 3:20:40 (22 Oct 2023, race) | 3:20:32 |

**Performance targets:** the Overview all-time view and the Wellness page render in under 300 ms server time on the full history; brushing Pace Trends, PR Progress and Wellness, and hovering the Overview charts, keeps every handler under about 16 ms on about 2,900 runs.

**Definition of done for a change:**

- `bin/rails test`, `node --test test/javascript/*_test.mjs`, `bin/rubocop`, `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`, `herb analyze .` and the Herb linter (`npx @herb-tools/linter app/views --simple --no-color`) pass.
- New logic has tests: Ruby for metrics and sync, `node --test` for interactive math.
- This document and `AGENTS.md` are updated in the same change.
- A browser check on a dev server, in light and dark, at 1300 px and 360 px: no sideways scroll, a clean console (the Herb dev-tools messages aside), the keyboard path works, tooltips escape their text, nothing lingers after a Turbo visit.
- No personal data in tests, logs or screenshots shared in reports.

## 12. Known limits

- The Personal API's rate limits are undocumented; throttle and back off anyway (§6.1).
- A Garmin key lasts at most a year; the banner and rotation steps are in §6.1 and §10.
- Strava's limits (100 requests per 15 minutes, 1,000 per day): a full link or gear scan is about 15 requests and the recent pass 1 an hour (§6.5).
- Health data sits in an app with no login; keep the host tailnet-only and never log health values (§10).
- Smashrun may shut down; its data is fetched once into stored originals, so nothing depends on it afterwards (§6.5).
- The Open-Meteo archive lags about 5 days (§6.4).
- Pro Map efforts are approximate on long runs because tracks keep at most 2,000 points (§4.8).
- Smashrun's estimated-finish widget has no documented stepping; ours steps 5K, 10K, Half, Marathon and wraps.

## 13. Landing site

- **Location:** `site/` in this repo, served at chartlek.com by Cloudflare Pages with no build command and output directory `site`. Pages serves only that directory, so the app is never exposed.
- **Files:** `site/index.html`, `site/styles.css`, the favicon set `site/icon.svg`, `site/favicon.ico` and `site/apple-touch-icon.png` (copies of the files in `public/`) and `site/screenshots/*.png` (copies of `docs/screenshots/`).
- **Constraints:** no JS, no framework, no build step, no analytics (§10), no external fonts or CDNs. Zinc neutrals with a lime accent, light and dark through `prefers-color-scheme`, system fonts, a single column on mobile.
- **Sections:** hero with the Overview screenshot and a GitHub button; interactive by design; a feature grid (Overview, Run page, Pro Map, Pace Trends, PR Progress, Wellness, Training Bands, Gear, Goals); your data stays yours; get started (requirements, `cp .env.example .env` plus `docker compose up -d`, a link to the README's "Run it yourself"); footer (GitHub, MIT license).
- **Copy** is condensed from the README and adds no features.
- **Licence and hosting:** MIT (`LICENSE`). There is no hosted version; the README's "Run it yourself" says everyone runs it on their own machine at their own risk and that it has no authentication.
