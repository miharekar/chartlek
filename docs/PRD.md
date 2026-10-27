# Smashback: Product Requirements Document

- **Status:** Draft v3. Phases 0 and 1 are done. Phase 2 is done (W1 to W5). Phase 3 (Wellness and gear) is done (W6 to W13). Phase 4 (Pro analytics) is planned.
- **Date:** 2026-10-27
- **Owner:** Miha Rekar
- **Repo:** `~/Projects/Personal/smashback`
- **Production:** https://run.rekar.eu (a Docker container, §9)

This document is the source of truth for scope. §14 is the ordered work queue with dependencies. Coding conventions are in `AGENTS.md` and `STYLE.md`. Each feature heading says whether it is built or planned.

## 1. Summary

Smashback is a local, single-user Rails app. It caches your Garmin Connect running history in SQLite and rebuilds Smashrun's charts, free and Pro, with a modern Tailwind UI and charts built directly on D3. It runs as a container at run.rekar.eu. Next it brings Garmin health data (HR zones, resting HR, HRV, sleep, Body Battery, stress) and Strava gear next to the runs, and after that the Pro analytics.

Why: Smashrun (smashrun.com/miharekar) is effectively abandonware, but its charts are still the best way to look at a long running history. The ask in [dreeveapp/dreeve#2880](https://github.com/dreeveapp/dreeve/issues/2880) was turned down because most of these charts are too runner-specific for a general-purpose app. Smashback is only about running, so it can include all of them.

## 2. Goals and non-goals

### Goals

- **G1:** Rebuild every Smashrun overview chart and the Pro analytics: Pace Trends, PR Progress, Training Bands, Progress Towards Goal, Pro Map, and the run page. Overview, Pace Trends, PR Progress and the run page are built; the rest is Phase 4.
- **G2:** Use the Garmin Connect Personal API as the primary source and cache everything in SQLite. The UI never waits on Garmin.
- **G3:** Fill the years before Garmin from the Strava API; take their tracks, and any Smashrun-only runs, from the Smashrun API.
- **G4:** Make the UI fast, modern and consistent: Tailwind, a System / Light / Dark theme switch, D3 charts as Stimulus controllers, and one design system (§10) in which every choice among options is a group of buttons.
- **G5:** Show Garmin health data on runs and in trends: HR zones, training effect and load, resting HR, HRV, sleep, Body Battery, stress and weight (§5.6); the probe found no readiness, recovery time, training status or VO2max in the Personal API data.
- **G6:** Show Strava gear, read-only: usage per shoe, and the runs that have no gear set, so they can be fixed on Strava (§5.7).

### Non-goals

These are explicitly out of scope:

- Badges.
- Anything social: friends, ranks, rarity %, invites, sharing.
- Weekly email report.
- Cooper test view.
- Local run tags, notes or edits.
- Running power (Stryd or native).
- Multi-user support and authentication. (It is deployed for the owner alone: a Docker container on their machine, §9.)
- Imperial units, including mile benchmarks.
- Writing anything back to Garmin or Strava, including gear.
- Gear maintenance, recording devices, bikes and shoe mileage alerts.
- Smashrun's SPI score and its trailing 90-day SPI comparison card. VDOT replaces SPI, and the VDOT view of "Runs in the prior 90 days" covers the comparison.
- A mobile app.

## 3. Decisions log

| Topic | Decision |
|---|---|
| Users | Just you. Single user, no accounts. |
| Hosting | One Docker container on your machine (port 9295), served at https://run.rekar.eu by Caddy on the Pi over Tailscale. `bin/dev` (0.0.0.0:3000, hosts `framework:3000` and `test.rekar.eu`) is for development. Both use the same SQLite dataset. No auth: the tailnet is the boundary (§9, §11). |
| Order of work | Finish Phase 2 (W1 to W5), then Phase 3 Wellness and gear, then Phase 4 Pro analytics. Wellness moved ahead of the Pro analytics because the Pro Map's HR colouring and Training Bands' HR category need the HR zones that Phase 3 stores. |
| Garmin access | [Garmin Connect Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api/). The key is in `.env` as `GARMIN_API_TOKEN`. |
| History gaps | Strava API (archive as fallback) for runs before Garmin, plus Smashrun for their tracks and the one Smashrun-only run. |
| FIT parser | `fit4ruby` from your fork `miharekar/fit4ruby`. `fit_kit` doesn't build on Ruby 4.0.9. The fork prefixes its BinData struct field names, so it works with bindata 2.4.10 and newer (CVE-2021-32823); bindata 2.3.1 made `type` a reserved name. An initializer quiets its logger and no-ops `Fit4Ruby::Activity#check`, its post-read validation, which rejects every 2024+ file and at least one older one. About 2,000 records/s. |
| Map | Mapbox GL JS for every map (run map now, Pro Map in Phase 4), loaded through Importmap (vendored UMD build, CSS vendored), with the `mapbox/light-v11` and `mapbox/dark-v11` styles following the chosen theme (the OS under System) and terrain layers on top (§5.5). The public `MAPBOX_TOKEN` from `.env` is rendered into the page. |
| Activity types | All running subtypes: road, trail, track, treadmill, indoor, virtual, ultra. Treadmill, indoor and virtual runs are flagged so they can be filtered out. |
| Performance index | VDOT only. SPI (Smashrun's 1 to 1000 score on a 1974 world-record curve) was dropped: its number has no physical meaning, and on the owner's PRs VDOT predicted other distances more accurately (§6). It is presented the Smashrun way: a zone strip and an estimated finish time you can step through the distances (§5.5). |
| Controls | Every choice among options is a group of buttons (a segmented control with `aria-pressed`). There are no `<select>` dropdowns anywhere (§10). |
| Gear | From Strava, read-only. Smashback never writes to Strava. Linked runs with no gear are flagged so you can fix them on Strava (§5.7). |
| Health data | Garmin Personal API, found out by a probe first (W6). What the API doesn't offer is cut from scope. Time in HR zones, training effect and training load come from the activity summaries already stored. |
| Units | Metric only: km, min/km, m, °C, 24h clock, weeks start Monday. |
| Look | Light and dark. A System / Light / Dark switch in the nav; System follows the OS, and the choice lives in a long-lived cookie rendered on `<html>` by the server. |
| Name | `smashback` |
| Stack | `rails new` (Rails 8.1.4, Ruby 4.0.9 via mise), SQLite, Tailwind, Importmap, Hotwire, D3, Solid Queue, Cache and Cable. Follows Visualizer's `STYLE.md` conventions. |

## 4. Phasing

| Phase | Ships | Exit criteria | Status |
|---|---|---|---|
| **0: Foundation** | App skeleton, Garmin client, activity sync from summaries, Strava archive import, nav and sync status | `Sync now` imports all Garmin runs. The Strava task imports only gap runs. Tests pass. | Done |
| **1: v1** | Overview (§5.2), Pace Trends (§5.3), PR Progress (§5.4) | All widgets per spec. Golden values (§12) within tolerance. Light and dark both verified. | Done |
| **2: Runs** | Original download and parsing (FIT, TCX, Smashrun recordings), runs list, run page (§5.5), weather, notables, food equivalents, Strava connection and run links, theme switch, linked hover, container deployment | Every run has a parsed track (Garmin original or Smashrun recording; two Smashrun details have none). Run page complete. | Done (W1 to W5: performance index and dynamic estimated finish, buttons instead of dropdowns, the rebuilt "Runs in the prior 90 days", one design system) |
| **3: Wellness and gear** | Garmin health data (probe first), HR zones and recovery on the run page, Wellness page, Pace Trends overlays, Strava gear sync and the Gear page (§5.6, §5.7) | Probe results are recorded in §7.1. Every run with HR shows its zones. The Wellness page shows every metric the API offers, for the whole history. Gear totals match Strava's and every linked run without gear is listed. | Done (W6 to W13) |
| **4: Pro analytics** | Pro Map (§5.8), Training Bands (§5.9), Progress Towards Goal (§5.10) | Per spec. | Planned (W14 to W17) |

Phase 3 does not depend on Phase 4. Phase 4 depends on Phase 3 for HR zones.

## 5. Feature specs

### 5.1 Global (built)

- **Nav:** Overview, Runs, Pace Trends, PR Progress. Phase 3 adds Wellness and Gear; Phase 4 adds Training Bands (between Wellness and Gear) and Goals (the Pro Map opens from a run). Items wrap instead of overflowing, and there are no dropdown menus. On the right: the sync status, **Sync now**, **Connect Strava** (or **Reconnect Strava** when the stored grant lacks gear access, §7.6) and the theme switch.
- **Sync status in the nav:**
  - Shows "Synced 12 min ago" and a **Sync now** button.
  - A sync runs every hour in the background (a Solid Queue recurring task in the container), and on the **Sync now** button. Opening a page does not sync.
  - A sync that created, changed or deleted runs, or that changed the error state, refreshes the page with a Turbo `:replace` refresh (`turbo_refreshes_with method: :replace`). Morphing would wipe the D3-drawn SVGs; a full replace makes the chart controllers reconnect and redraw.
  - Any other sync only replaces the nav sync status in place. The status also shows "Syncing…" live when a sync starts, and no page state (modes, selections, brushed windows) is lost.
  - If the Garmin key has expired, a banner explains how to rotate it (§11).
- **Theme:** System, Light or Dark. The choice is stored in a long-lived cookie and rendered on `<html data-theme>` by the server, so nothing flashes; a switch is a full page load, because Turbo doesn't update `<html>` attributes.
- **Controls:** a choice among options (metric, window, mode, distance) is a group of buttons with `aria-pressed`; independent filters are toggle buttons; actions are buttons. There is no `<select>` (§10).
- **Formatting:**
  - Pace: `m:ss /km`.
  - Durations: `h:mm:ss`.
  - Distances: 1 decimal place in km, everywhere (tooltips included).
  - Dates: `21 Apr 2020`.
  - Numbers use `tabular-nums`.
- **Links:** clicking a run in any chart opens its run page in the same tab. The run page links out to Garmin or Strava.
- **Chart info:** every chart has an ⓘ button explaining how to read it, adapted from Smashrun's FAQ. The text shows in the shared tooltip on hover, keyboard focus or tap, and Escape or a click elsewhere hides it.
- **Empty states:** a page with no runs or no data shows an empty state instead of charts.
- **Keyboard and focus:** a chart's interactive elements are one Tab stop with Arrow, Home, End and Escape. A mouse click on a chart that has no click action never leaves a focus outline or pins a tooltip; keyboard focus (`:focus-visible`) shows a ring.

### 5.2 Overview (Phase 1, built)

Routes: `/` → `/overview`, `/overview/:year`, `/overview/:year/:month`.

The period selector offers **All time**, a pill for every year (newest first), and month pills for the selected year (months without runs are disabled). The period applies to every widget.

The header row has a **Latest run · date · km →** button linking to the newest run overall, on every period (absent when there are no runs).

| # | Widget | Spec |
|---|---|---|
| 1 | Kilometers run | Big total with the number in English words underneath, Smashrun-style ("thirty three thousand four hundred sixty four"). Run count. |
| 2 | Average run length | km |
| 3 | Average days run per week | Distinct run days ÷ weeks in the period. For all time, the period runs from the first run to today. |
| 4 | Time of day | % of runs starting after noon (local time), with a small AM/PM donut. |
| 5 | Average pace | Total timer time ÷ total distance. |
| 6 | Longest run | km and date; links to the run. |
| 7 | Distance per period | Bars: per month (all time), per week (year), per day (month). A button group beside the title chooses the metric: **Distance**, Elevation gained, Avg distance, Avg pace, Avg VDOT, and the title follows it. Hover shows value and run count. Clicking a bar drills into that period. |
| 8 | Trailing days | Daily rolling sum of distance: 365 days (all-time view), 90 (year), 7 (month). |
| 9 | Runs pace vs distance | Scatter of runs in the period. x = km. y = pace on a speed-linear axis labeled as pace (ticks 4:00, 5:00, 6:00, 7:30, 10:00, 15:00, 30:00). The last run is a plain amber dot, a little larger than the others and without an outline; it hides while a linked hover selection is active (every selected dot is amber then) and returns when the selection clears. The average is a ring marker. A button group chooses the y metric: **Pace**, Avg HR, VDOT. |
| 10 | Consecutive days run | Longest streak and longest break with dates, plus the current streak or break. |
| 11 | Weekly stats for each year | All-time view: heatmap with years as rows and Monday-start weeks as columns. Weekly km buckets: >1, >20, >40, >50, >60 (ring), >80 (dot). Year and month views show a day calendar colored by daily km instead. |
| 12 | Personal records | Benchmarks: 3 km, 5 km, 10 km, 15 km, 20 km, half marathon, 40 km, marathon, 50 km, 100 km. Only benchmarks with qualifying runs in the period are shown. Each row: date, pace, km/h, time, number of runs in the bucket, and a race tag next to the distance. Below `sm` the km/h and Runs columns are hidden, so the table doesn't scroll sideways at 360 px. |

**Linked hover (Smashrun-style).** Hovering one of the charts below selects a set of the period's runs and highlights them in the others; leaving clears it. The chart under the pointer keeps its own tooltip and click. Hover also works over a chart's axes and their margins: the bars and the trailing line treat the bottom axis as the nearest column or day. On the scatter, selected runs are drawn larger in amber, the others muted grey, and the mean ring (the legend's lime ring) thickens; with no selection the chart looks as usual.

| Hover | Selects |
|---|---|
| Trailing line, at day d | the runs in the N days ending at d (N is the chart's window, 365, 90 or 7), among the period's runs |
| Scatter, at the cursor in the plot | the runs plotted strictly further right and strictly higher (longer, and faster or higher on the y metric) than the cursor |
| Scatter, over the bottom axis | every run longer than the cursor's x, at any pace |
| Scatter, over the left axis | every run above the cursor's y (faster, or higher HR or VDOT), at any distance; the bottom-left corner selects nothing |
| Distance bars, at the cursor | every run of the period whose column is under the cursor (the full chart height counts, and gaps snap to the nearest bar); that bar stays at full opacity and the others dim |
| Heatmap cell | the runs of that week (all time) or day |
| Heatmap legend bucket | the runs in every cell of that bucket |
| Longest / current streak or break | the runs in that span (none for a break) |

| Chart | Shows the selection as |
|---|---|
| Scatter | the selected dots in the highlight colour and the rest faded; the average ring moves to the selection's mean (km-weighted pace, plain mean of HR and VDOT). An empty selection keeps the ring where it was |
| Bars | the selection's share inside each bar (by km for Distance, by metres gained for Elevation, by run count for the averages) over a faded bar |
| Heatmap | every cell outside the selection faded (a streak or break fades the cells outside its dates; hovering a cell itself fades nothing) |

The selection is only for the current view, is published through one shared module that redraws just the highlight layers once per animation frame, and is mouse driven.

### 5.3 Pace Trends (Phase 1, built)

This answers "am I getting faster?" by putting all distances on a common scale (VDOT).

**Main chart**

- x = date, y = VDOT.
- Every run is a small muted dot.
- **Top runs** are accent (yellow) dots joined by a faint smoothed line. A run is a top run if it is in the top 3 by VDOT within the 30 days ending on its date (see §6).
- A **regression band** shows the least-squares line through the top runs inside the selected window, ±1 SD of the residuals.

**Timeline and window**

- Below the main chart, a timeline of bars shows each run's duration in hours over the whole history.
- A `d3-brush` on the timeline selects the window; the default is the last 12 months. The main chart zooms to the window.
- **Presets:** a button group above the chart sets the window in one click: 3 mo, 6 mo, 1 yr, 2 yr and All time. Each ends at the end of today (the date of the latest run, as for the default) and starts that many calendar months earlier, clamped to the month's length; All time starts at the first run, and a span longer than the history also starts there, in which case the longer preset is the one marked. The preset matching the current window has `aria-pressed`; the default (12 months) marks 1 yr. A preset moves the brush and updates the stats, top runs, regression and finish predictions like a drag. A drag or resize clears the mark unless the new window equals a preset exactly. The window stays in the `from` and `to` URL params, so reloads, links and the filter chips keep it. PR Progress has no presets.
- The header shows:
  - The date range.
  - "Change in VDOT: **+0.05/week**", the slope × 7, always with two decimals.
  - "Cut **34:28** from your estimated **5K / 10K / Half / Marathon** finish time", where the distance is a button group. This is the predicted time at the chosen distance, using the regression VDOT at the start of the window versus the end. If the result is negative, it reads "Added".
- The regression and header are recomputed in the browser while dragging, with no server round trip.

**Filters**

Toggle buttons:

- Exclude runs with pauses.
- Races only (Garmin event type `race`).

**Tooltip**

Shows date, name, VDOT, distance, pace and time. Clicking a run opens its run page, which includes the 90 days of training before that run.

**Overlay (Phase 3, built, W10)**

A button group above the main chart chooses None (default), Resting HR or HRV, drawn as a thin muted line on a secondary right-hand axis (§5.6). An option appears only when `WellnessDay` has that series, and the whole group is hidden without wellness data. The choice is the `overlay` URL param (`rhr` or `hrv`, kept like `distance` by the preset, brush and filter chip links; unknown or empty values mean None).

### 5.4 PR Progress (Phase 1, built)

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
2. The reference run is the run with the highest VDOT in that period. It is shown and can be changed by clicking another run.
3. The chart draws the predicted time at each benchmark at the same VDOT, from the VDOT time tables.
4. Predictions that beat the all-time PR are highlighted. Tooltips show predicted time, pace, and % improvement over the current PR.

**"Magic PRs"**

1. For each benchmark, the target is the next round time below your current PR.
2. Steps: 1 min for distances ≤ 5 km, 5 min up to the half marathon, 15 min for longer. For example: 5 km 24:23 → 24:00, half 1:37:30 → 1:35:00, marathon 3:20:32 → 3:15:00.
3. The 3 targets with the smallest % gap are shown as pulsing markers, with tooltips like "Sub-3:15 marathon: shave 5:32 (2.8%)".
4. The step table is a constant and easy to tune.

### 5.5 Runs list and run page (Phase 2, built; finished by W1 to W4)

**Runs list (`/runs`, filterable by year and month)**

- Sortable table: date, name, km, time, pace, HR, elevation, VDOT. The VDOT header carries the explanation (§6).
- Race, PR (Garmin's own personal-record flag, `pr` in the summary) and treadmill tags.
- Phase 3 adds a Gear column and a `gear` filter (§5.7).

**Run page (`/runs/:id`)**, top to bottom:

1. **Header**
   - Local date and time, start-end clock time. The date line, the gear line and the weather line share one type and colour (`WidgetsHelper::HEADER_LINE`).
   - Gear (§5.7), on its own line under the date and above the weather: a small sneaker icon and the gear name linking to that gear's runs list, or an amber "No gear" prompt for a linked run with no gear. Runs without a `strava_id` have no gear line.
   - Weather, from Open-Meteo at the run's midpoint hour, as one line of icon and value items (`run_weather`): the condition from the WMO code with its label (clear, partly cloudy, cloudy, fog, drizzle, rain, showers, snow, thunderstorm; clear and partly cloudy turn to a moon when the midpoint is outside sunrise to sunset), then temperature, humidity, wind and, only above 0, rain, each as an icon and its value (`14°C`, `60%`, `8 km/h`, `1.2 mm`); the words "humidity", "wind" and "rain" are `sr-only` text for screen readers. The icons are inline SVG and decorative, the text carries the meaning, and a missing field leaves no item. Runs without weather show nothing.
   - Location name (Garmin only), previous/next run, and Open in Garmin and Open in Strava buttons side by side. Garmin shows for Garmin runs; Strava shows for runs with a `strava_id` (§7.6). A Smashrun-only run has neither. The gear line is above.
   - If there were several runs that day, a switcher between them.
   - A Smashrun-style date navigator: every year with runs (newest first), the 12 months of the run's year, and every day of its month, with the run's year, month and day selected. A year or month with runs opens its latest run, and a day opens its first run; the others are inert. Weekends look distinct, race days are amber, and hovering or focusing a day shows its weekday, date and distance in the shared tooltip. (Smashrun's own year and month buttons open its overview pages instead.)
   - **Notables** (§6) as compact chips right under the header, above the tiles, wrapping on narrow screens; each chip carries the notable's full text, and a run with none shows nothing.
2. **Tiles and cards**, a grid of 4 columns on wide screens and 2 on narrow ones:
   - Distance, elapsed/timer/moving time, average pace and speed. Runs whose Garmin summary has a positive `avgGradeAdjustedSpeed` (1,077 of 2,515, from 2022-06) add a "GAP 5:02 /km" line under the speed, with an ⓘ explaining grade-adjusted pace (`Activity::Performance#grade_adjusted_pace`, s/km). The run title carries a PR chip next to the race chip when Garmin flagged the run (5 runs).
   - Calories with a food equivalent ("A bunch of bananas… or a kremšnita").
   - Average HR (min-max) and average cadence (min-max).
   - **Performance index and estimated finish** (W1). One card, two columns wide, in two halves. It replaces the VDOT tile and its 2×2 grid of finish times. Smashrun's version is built on its SPI; ours is built on VDOT.
     - **Performance index** (ⓘ with the VDOT explanation, §6): the run's VDOT as the big number (one decimal, a dash when the run has none) and under it a strip of the pace zones (§6) that matter for this runner, in the shared colour ramp: the range, not all 37 zones, so the dot isn't lost in the middle of a rainbow the runner never reaches (§6, Performance zone). A dot marks the zone of the pace at which this VDOT would run a 5K, labelled with that pace ("5K pace 4:52 /km"); a zone's own label shows on hover.
     - **Estimated finish:** the predicted time at this VDOT for one distance at a time: the time big (h:mm:ss), the distance label (5K, 10K, Half, Marathon, the same list as Pace Trends) and the pace it implies. A ▶ button next to the label steps to the next distance and wraps from Marathon back to 5K; the default is 5K, and the time is announced with `aria-live="polite"`. All four times are already on the page, so stepping makes no request.
     - A run without a VDOT (under 400 m) shows dashes and no strip.
   - **Pace variability**, drawn as Smashrun's wheel: a ring of equal-angle wedges, clockwise from 12 o'clock, one per 100 m of the run (the same 100 m bars as the speed chart; a final bar shorter than 100 m is dropped, and there is no grouping or cap, so a 10 km run has 100 wedges and a marathon about 422), all in the accent colour, with the stored variability % (the average speed deviation across complete 10 s windows, not computed from the wedges) in the hole. A wedge's outer radius is the bar's |speed − mean| / mean (mean over the wedges) plus a 0.25 base, over a domain of 0 to the larger of 0.75 and the largest value, so a longer wedge means a speed further from the average, faster or slower. Hover or focus shows the wedge's distance range, its pace and the signed "Speed vs average" (for example +8.3%); the wheel is one Tab stop with Arrow, Home, End and Escape. An ⓘ explains it. The wheel needs at least two whole 100 m bars; runs without a track show the percentage and "Recording chart not processed yet."
   - **Nth longest run** and **Nth fastest for a similar distance** (±10%), each with a histogram: distance in km across all runs, or pace in min/km across the same similar-distance cohort. Bar height is run count; amber marks the current bucket and exact value. Hover shows the range, count and current value. Ties share a rank; cohorts include all dates. The histogram spans the 2nd to the 98th percentile in equal-width bins (at most 12), and the tails fold into open-ended first and last bins labelled "<x" and ">y", so a few extreme runs can't squash the rest (§6).
   - **Elevation profile** (shown when the run has altitude or an elevation gain; without altitude the card is titled "Elevation" and has no chart, only gained, lost and hill difficulty): a compact card with a 70 px line chart of altitude against distance on the left (about two thirds) and, on the right, gained (+m), lost (−m) and **hill difficulty**. There are no axes or grid; the y domain is the low point − 5 m up to the larger of the low point + 150 m and the high point, so a flat run looks flat, and an amber dot marks the highest point. Hovering snaps a dot to the nearest sample and shows its elevation and distance. Gained and lost are the run's stored totals; there is no separate Elevation tile. Hill difficulty is explained in §6 and in the card's ⓘ.
   - **Packing rule:** the grid must pack without empty cells at the base, `sm` and `lg` breakpoints, with or without HR, cadence, altitude (the elevation profile card), pace variability and VDOT; the implementer chooses spans per combination. The Elevation tile may fold into the elevation profile card, which already shows gained and lost.
3. **Route map:** immediately after the tiles, a Mapbox GL JS route line, 600 px tall on desktop and 320 px on phones. Requires a GPS route and the public Mapbox token. Under the light or dark base style (following the theme) it shows terrain for trail runs: subtle hillshading, contour lines (stronger index contours with elevation labels in metres), and mountain peaks as ▲ with name and elevation in metres. The terrain sits below the roads and labels, and the route and its start and end markers stay on top. No toggle. The Pro Map comes in Phase 4 (§5.8), also on Mapbox GL JS.
4. **Change in speed over route:** only for tracks with splits. Bars per 100 m, switchable to per-km splits with a two-button toggle (pressed state, keyboard accessible). Brushing a range shows a summary of the selection: distance, time, pace, HR, cadence. There is no separate elevation-change chart: elevation lives in the elevation profile card and the profiles chart.
5. **Elevation, HR and cadence charts:** 180 px each, sharing the distance x-axis. Chart sections require a track. **One distance cursor** ties the run page together: hovering the speed chart, the profiles (elevation, heart rate and cadence share one line and their readouts) or the elevation profile card draws a vertical amber line at that distance on all of them, and moves a small amber marker with a halo along the route on the map (no panning or zoom). Each chart keeps its own tooltip, and leaving any of them clears the line and the marker. Runs without a map (indoor) still sync the charts.
6. **Heart rate zones and effort, Going in** (Phase 3, §5.6).
7. **Fastest runs for this distance:** for the last 90, 180 and 365 days and for all time (five rows each, the current run highlighted when it is listed).
8. **Runs in the prior 90 days** (the Analyze Run View; rebuilt in W3 (built) to follow Smashrun's layout, which the owner likes: https://smashrun.com/jacklyn.giron/run/14325559, read-only, nothing from it is stored). The window runs from midnight 90 days before the run's day up to the run's start. This run is never part of the averages or readouts. Top to bottom:
   - **Title row:** the title with an ⓘ, and a button group for the metric: Distance (default), Pace, VDOT, Heart rate.
   - **Dot strip:** a one-dimensional dot plot across the full width. Each previous run is a semi-transparent circle placed on the chosen metric's axis, so overlaps read as density. This run is a smaller amber dot drawn on top. A thin accent bar marks the mean of the previous runs; runs without the metric are skipped, and a zero or missing HR counts as missing. Axes (this run's value is included): distance from 0 to the longest run rounded up, plus 1 km; pace as speed, from 4 km/h (lower only if a run is slower) to the fastest speed plus 1 km/h, labelled as pace, faster to the right; VDOT from the lowest minus 1 to the highest plus 1; heart rate from the lowest to the highest, rounded out to 10 bpm. About seven ticks. Switching the metric glides the dots to their new positions (about 400 ms); runs without the new metric fade out.
   - **Brush:** dragging across the strip selects the runs whose value is inside it. The others dim, the mean bar hides, the axis shows only the two edge values, and the matching days light up in the timeline. A readout floats above the brush with a small pointer; clicking it cycles four views: share of the previous runs (a whole percent, the default), hours, distance and run count. Clicking outside the brush, or Escape, clears it. A summary line stays under the title: run count, distance, duration and share of the window's training distance, for the selection or for all runs. It is also the text equivalent for assistive tech.
   - **Timeline:** one mark per run day from 90 days before to the run's day, each one day wide and full height (no height encoding); this run's mark is amber at the right edge. Ticks read "90 days before", "60 days before", "30 days before" and "run day" ("race day" for races); under about 140 px per label only the first and last show. A run day that also has earlier runs splits its column: earlier runs on the left half, this run on the right. Hovering a day highlights it and shows a tooltip: the date, "N days before" (or "yesterday"), and each run that day with its distance and pace. The matching dots in the strip light up too, and with a brush active only the runs inside it do. Clicking a day opens its first run (the run page's same-day switcher reaches the others) and hides the tooltip.
   - **Dots:** hovering a dot shows its date, distance, pace, HR and VDOT; clicking opens that run. A click on a dot opens its run, while a click on empty strip clears the brush. The strip is one Tab stop; Left, Right, Home and End move between dots in value order (the tooltip follows) and Enter opens the run.
   - **Legend** (hint style): a dot for "This run", a bar for "Average" and a large dot for "Previous runs".
   - **Empty:** with no runs in the window it says "No runs in the 90 days before this one."

### 5.6 Wellness (Phase 3, planned)

Garmin health data next to the runs, in three places: the run page, a Wellness page and Pace Trends. The W6 probe (§7.1) found what the Personal API offers: resting HR, HRV, sleep (from Garmin's documented `dailySleep` paths, found in the second probe round), stress, Body Battery, weight and HR zones. **Cut because the API has no endpoint: training readiness, recovery time, training status and load, and VO2max** (the run summaries carry none either). The owner decided to leave out whatever the API lacks (R10), with no data-export import.

Some of it needs no new endpoint, because the stored activity summaries already carry it (checked on a recent run): time in each of the five HR zones, aerobic and anaerobic training effect with its label, training load, Body Battery change, intensity minutes, and running dynamics when the watch records them (ground contact time, vertical oscillation, stride length, vertical ratio).

**HR zones**

- Zone boundaries (bpm) and max HR live on the profile (`profiles.hr_zones`), read from `GET /biometric-service/heartRateZones/v2` (verified in W6: per-sport `zone1Floor` to `zone5Floor` and `maxHeartRateUsed`). If that call fails or has no entry, zones are Garmin's default %max bands (50, 60, 70, 80 and 90% of the highest max HR recorded), and the pages say so. One small PORO (`HrZones`) turns a bpm into a zone and a zone into its bpm range, so the run page, the HR profile and the Phase 4 features agree.

**On the run page** (new sections after the elevation, HR and cadence charts)

- **Heart rate zones and effort (built, W8):** a card after the elevation, HR and cadence charts. One stacked horizontal bar of time in zones 1 to 5 (Garmin's `hrTimeInZone_1` to `_5` from the stored summary), with each zone's minutes, percent and bpm range under its label (Z1 to Z5 on phones). The bar has a text equivalent (its `aria-label` lists every zone) and is one Tab stop: Arrow, Home and End move between segments, the shared tooltip follows, Escape hides it. Zone colours are the `--hr-zone-1` to `--hr-zone-5` CSS variables (blue, green, yellow, orange, red; one set for light and one for dark), which the Pro Map's HR colouring (W14) reuses. Below the bar: aerobic and anaerobic training effect (0 to 5, with Garmin's label under the aerobic one), training load, Body Battery change, intensity minutes (moderate and vigorous), and a running dynamics row (ground contact, vertical oscillation, stride length, vertical ratio) only when recorded. A field the run lacks is left out; a run without zone times (no HR, and every pre-Garmin run) has no card. Without Garmin's zones the card says the ranges are the default bands. The HR chart in the profiles section draws faint horizontal bands for the zones behind the line, for any run with an HR track, and the HR line itself takes the colour of the zone it is in, changing exactly at each zone boundary (a darker shade of the zone colour in light, a lighter one in dark, so it reads on top of its own band); with no zones it is the accent colour. Garmin timed each zone with the zones in force when the run was recorded, but nothing stores those, so the bpm ranges (legend, tooltip, chart bands) are today's zones; the card says so in a hint and its ⓘ. Zero effort values (training effect, load, Body Battery change, intensity minutes) are left out like any missing field.
- **Going in (built, W8):** a card for the run's local day (`local_started_at.to_date`) from one `WellnessDay` lookup: resting HR with its 7-day average, last night's HRV with its status and baseline band, last night's sleep (duration and score), and Body Battery at wake. Values that are nil for that day are left out, an empty marker row counts as nothing, and with nothing left the card is omitted. The day's average stress is not shown. Layout: the two cards share a row at `lg` (zones two thirds, Going in one third), stack at base and `sm`, and either alone spans the full width; the tiles inside wrap and stretch, so no combination leaves an empty cell.

**Wellness page (`/wellness`, built, W9)**

- Nav item **Wellness** (between PR Progress and Gear). A shared window: the Pace Trends presets (3 mo, 6 mo, 1 yr, 2 yr, All time, default the last year) and a brush on a compact daily resting HR timeline (`createTimeline` and the preset helpers are reused), with `from` and `to` in the URL. Every chart below follows it. Hovering any chart draws a vertical line at that day on all of them, through the run page's cursor module (`helpers/run_cursor`, which carries epoch ms of the day here and metres there). The overlay of each chart is one Tab stop: Left and Right step the shared cursor by a day, Home and End jump to the window's ends, Escape clears it, and the tooltip anchors to the cursor line.
- Charts, each shown only when its data exists (one card each, all in one `wellness` Stimulus controller):
  - **Resting HR:** daily dots with the 7-day average line (§6, computed in JS from the series, with at least 4 values in its 7 days, and none on a day without a reading).
  - **HRV:** the nightly average as a thin line, with one dot per night coloured by Garmin's status (balanced accent, unbalanced amber, low and poor red, anything else muted), over the baseline band (low to high).
  - **Sleep:** one bar per night, stacked by stage (deep, light and REM, in the accent colours, so the bar is the time asleep; the awake time is in the tooltip), with Garmin's sleep score as a line on a right-hand 0 to 100 axis. Nights from before Garmin recorded stages (until early 2018) are one unstacked bar, and the score exists from about 2021. A night belongs to the date Garmin gives it, the wake-up date. The tooltip adds the average heart rate and stress during sleep.
  - **Body Battery:** a bar per day from its low to its high, with the value at wake as an amber mark.
  - **Stress:** the daily average as dots and a thin line.
  - **Weight:** measurements as dots with the 30-day centred moving average as the line (§6).
  - **Top-run VDOT:** the Pace Trends top-run VDOT line. VO2max is not shown: no Garmin Personal API activity summary carries it (0 of 2,869 runs have a `vO2MaxValue`) and the `maxmet` endpoints are 404 (§7.1), so by the owner's rule (R10) it is left out.
  - **Time in HR zones per week:** stacked bars (zones 1 to 5, hours, weeks start on Monday), summed in SQL from the run summaries' `hrTimeInZone_*`, in the `--hr-zone-N` colours. Weeks without a timed run have no bar.
- Missing days are gaps, not zeros: the days are sent densely (one entry per day from the first to the last day with a value, `null` where there is none), so a line breaks at a gap; an empty-marker row counts as no data. Before a device recorded a metric, its chart simply starts later (and is empty when the window ends before that).
- Data: `Wellness::Trends` builds one payload (columnar JSON: `start`, `domain`, `window`, a dense array per series, and tuple lists for VDOT and zone weeks; about 165 KB on the full history) from five queries. With no wellness data at all the page shows an empty state.

**Pace Trends overlay:** the button group above the main chart (None, Resting HR, HRV, Sleep) draws the chosen series on a secondary right-hand axis in a muted colour. Resting HR is the 7-day average, HRV the nightly value and Sleep the night's hours (the night before the run's day); a missing day is a gap in the line. The second axis is fitted to the window and follows the brush, the tooltip gains a line with the value for the run's day, and the regression, stats and predictions don't change. Data: `Wellness::Trends#overlay` (the dense `rhr`, `hrv` and `sleep` columns and their start, about 25 KB on the full history), sent in the Pace Trends payload so switching needs no request; the averaging is `movingMean` in JS, as on the Wellness page.

### 5.7 Gear (Phase 3, built)

Strava gear, read-only (§2). Modelled on the Gear page of the owner's Dreeve instance (strava.rekar.eu/gear), but for running shoes only.

- **Source:** each Strava run carries a `gear_id` (null when no gear is set), and each gear has a name, brand, model and description (§7.6). Gear reaches our runs through the existing `strava_id` link, so only runs linked to Strava have gear information.
- **Gear page (`/gear`):**
  - **Active gear table:** one row per gear, most used first: name (brand and model under it), runs, distance, moving time, distance in the last 12 months and last used date. Retired gear sits under a collapsed "Retired (n)" toggle button. Distance and time are summed from our runs, not taken from Strava's gear totals.
  - **No gear set:** a separate amber row for linked runs with no gear (count, distance, last run), linking to the runs list filtered to them.
  - **Distance per month per gear:** stacked bars.
  - **Distance over time per gear:** cumulative lines. In both charts a toggle button per gear turns it on or off; retired gear starts off. Both x axes cover only the visible gear, from the first month any of it was used to the last (the lines start one month earlier, at zero), and redraw on every toggle; with no gear visible the full range stays. Up to 18 months the bars are labelled by month, longer by year.
  - **Refresh from Strava:** a button that starts a full gear scan (about 15 requests).
  - Until the first gear scan has finished, the page says so, instead of listing every run as having no gear.
  - Gear Strava never returned (a 404 on `GET /gear/{id}` for an id with no stored payload, so a row with a nil `name` and `summary`) is listed by its Strava id in the active table, with the runs and distance our runs still carry for it, under a "Gear no longer on Strava" label. A gear fetched before keeps its stored name and details when a later fetch gets a 404; only its `synced_at` moves.
- **Fixing runs with no gear:** `/runs?gear=none` is the runs list limited to those runs, with an extra **Suggested** column (the gear used most in the 14 days either side) and an Open in Strava button on each row. You set the gear on Strava; the run leaves the list after the next hourly recent scan (the last 30 days) or a manual refresh.
- **Runs list and run page:**
  - the list gets a Gear column and the `gear` filter (one gear, or `none`);
  - the run header has a gear line (sneaker icon and the gear name linking to that gear's filtered list, or an amber "No gear" link to `/runs?gear=none`) under the date and above the weather;
  - runs without a Strava link show neither, since their gear is unknown rather than unset.

### 5.8 Pro Map (Phase 4, built, W14)

A full-page view at `/runs/:id/map`, opened from the run page's route map ("Open Pro Map"). Runs without a GPS route (or without the public Mapbox token) have no button, and the URL redirects to the run page.

- **Route coloring:**
  - The route is split into segments and colored by the selected metric (a button group; metrics a run lacks are left out):
    - **Pace:** the 37 pace zones (§6) in the shared colour ramp, from walking (dark red) to "zoom" (white), fixed across all runs so that improvement is visible. Needs the run's splits, so rebuilt-distance runs lack it.
    - **HR:** your HR zones (§5.6), `--hr-zone-N`.
    - **Grade:** −10% to +10% in 2% buckets (the outer ones take anything beyond), from altitude over 200 m windows.
    - **Cadence:** under 150, then 10 spm ranges up to 190+.
  - Map tiles follow the chosen theme (the OS under System), with the terrain layers of §5.5.
- **Distribution bars** under the map, one per bucket of the current metric (time share), using Smashrun's click cycle: 1× selects only that bucket, 2× that bucket and above, 3× that bucket and below, 4× resets. The selection stays bright on the map and the rest dims. The legend shows distance, duration, average pace, HR and cadence for the selection.
- **Fastest segments:** 250 m, 400 m, 1 km, 5 km, 10 km, half marathon and marathon, up to the run's length, each with time, pace and VDOT (none under 400 m). They are computed on the fly from the stored track (`Track::Efforts`), not stored. The track keeps at most 2,000 points, so on long runs a segment's start, end and time are approximate (the ⓘ says so). Clicking one isolates it on the map and updates the stats; clicking again clears it.
- **Splits** per km, showing the current metric's column (pace, HR, elevation or cadence). Clicking a split isolates it.
- **Change-in-pace graph** under the map (pace per 100 m). Hovering a metric button overlays that metric on a secondary axis, and hovering the graph moves a marker on the map through the shared run cursor.

### 5.9 Training Bands (Phase 4, built, W15)

- **Precomputed per run:** `activities.bands` (JSON) holds seconds per pace zone (the 37 zones of §6), per HR zone (1 to 5, `HrZones.current`) and per grade bucket, computed by `Track::Bands` from the stored track (`tracks.data`: `t`, `d`, `alt`, `hr`), never from the originals. `process_original` sets it for new runs and `bin/rails activities:bands` backfills it from the stored tracks in a few seconds (the originals would take hours). A run with a rebuilt distance (§6) has no bands, like its splits.
- **How a run is cut:** the track is walked in windows that close at 100 m or 30 s, whichever comes first, so stopped time lands in the walk zone. A window's speed gives its pace zone; its mean HR (missing HR is skipped, a bpm under zone 1's floor counts as zone 1) gives the HR zone with today's boundaries; its altitude change over its distance gives the grade bucket (windows under 20 m, or without altitude, are left out). The 100 m window is the smoothing, so GPS altitude noise within about a metre doesn't leave the flat bucket. Grade buckets: below −8%, −8 to −4, −4 to −1, −1 to +1, +1 to +4, +4 to +8, above +8%.
- **Page (`/training_bands`, nav item Training Bands between Wellness and Gear):** one stacked area chart of time per week (weeks start on Monday, `local_started_at`) across all history.
  - **Category** (button group): Pace, Heart rate, Grade; Heart rate is only offered when some run has HR bands.
  - **View** (button group): Absolute (hours per week) or % (each band's share of the week's total running, so hiding bands leaves the shown share rather than rescaling to 100%).
  - **Band filters:** one toggle button per group, all on by default, with a swatch of the group's colours. Pace groups: Walk (under 5.5 km/h), Easy (slower than 6:00 /km), Steady (6:00 to 5:00), Tempo (5:00 to 4:17), Fast (faster than 4:17), the boundaries fixed, not personal; so "tempo and faster" is Walk, Easy and Steady turned off. HR groups are the five zones ("zone 4+" is zones 1 to 3 turned off), grade groups the seven buckets. Filters are kept per category for the visit, not in the URL.
  - **Window:** the Pace Trends presets (3 mo, 6 mo, 1 yr, 2 yr, All time, default All time) and a brush on a timeline of weekly hours (`createTimeline` and the preset helpers are reused). `from`, `to`, `category` and `view` are URL params, updated in place.
  - **Colours:** pace bands use `--pace-zone-N`, HR bands `--hr-zone-N` and grade `--grade-0` to `--grade-6` (blue for descents through grey to orange and red for climbs), so a colour means the same as on the run page and the Pro Map.
  - **Tooltip:** hovering a week (or Left, Right, Home, End and Escape on the chart's Tab stop) lists each shown group's time and share of the week, then the week's total.
  - **ⓘ:** explains the groups and says the HR zones are today's, as on the run page.
- **Performance:** the payload is columnar, one dense array of weekly seconds per band (bands with no time left out), about 170 KB on the full history, summed in Ruby from one query. The page took about 50 ms server-side once warm (161 ms the first request) and a window change or filter toggle redraws in about 5 ms.

### 5.10 Progress Towards Goal (Phase 4, planned)

**Goals**

- Monthly and yearly distance goals, stored locally with CRUD.
- They also appear as widgets on the Overview, as on Smashrun.

**Chart**

- An accent line shows cumulative distance. A grey line shows the direct path to the goal (goal ÷ days).
- Hovering a past date shows where you were. Hovering a future date shows the required average distance per day from now on.
- When you're behind, a red catch-up line appears. Its intensity is the required daily distance relative to your recent daily average.
- The x-axis has ticks on run days with daily totals; clicking one opens that run.

## 6. Metrics and formulas

All metric math lives in Ruby and is unit-tested. The only JS math is interactive recomputation (regression, brush stats, cycling, hover selection), and it has `node --test` tests.

- **Run eligibility:** an activity counts if its type is a running subtype and its distance is ≥ 0.1 km. Treadmill, indoor and virtual runs are counted but flagged.
- **Time basis:**
  - `timer_s` is Garmin's `duration`, which excludes manual pauses. It drives pace, VDOT and PRs.
  - `elapsed_s` and `moving_s` are also stored.
  - A run *has pauses* when `elapsed_s − timer_s ≥ 60`.
- **Local time:** all day bucketing (streaks, weekdays, AM/PM, calendars) uses Garmin's `startTimeLocal`. UTC is stored as well.
- **VDOT** (Daniels–Gilbert):
  - v = m/min, t = minutes.
  - VO2 = −4.60 + 0.182258·v + 0.000104·v²
  - %max = 0.8 + 0.1894393·e^(−0.012778·t) + 0.2989558·e^(−0.1932605·t)
  - VDOT = VO2 / %max
  - `nil` for runs under 400 m or a time ≤ 0.
  - The explanation shown in the app (an ⓘ next to the run page's performance index, the Pace Trends title and the runs table's VDOT header): "VDOT is Jack Daniels' estimate of the VO2max a run implies, on the same scale as your watch's VO2max. It puts every distance on one scale, and one point is worth about 2% of race time. Easy runs score lower because they aren't all-out." followed by example times for VDOT 45 and 50, computed from `Vdot.time_for` so they can't drift from the model (VDOT 45 ≈ 5K 21:49, 10K 45:13, half 1:40:14, marathon 3:28:16; VDOT 50 ≈ 19:56, 41:20, 1:31:31, 3:10:40).
  - **Why VDOT and not SPI:** VDOT (Jack Daniels, 1979, still the basis of *Daniels' Running Formula*) is the VO2max a run implies, on the same scale as the VO2max a watch shows. SPI is Smashrun's 1 to 1000 score, built on a 1974 world-record curve, and its number has no physical meaning. Predicting each of the owner's 10K, half and marathon PRs from the other two, VDOT was off by 2.0% on average and SPI by 4.8%. From the 10K PR, SPI predicted a 3:31 marathon and VDOT 3:17; the actual PR is 3:20:40.
- **Predictions and estimated finish:**
  - Time at distance D for a given VDOT comes from inverting the VDOT formula numerically (`Vdot.time_for`, bisection).
  - `Vdot.time_table(distance)` ships a lookup table per distance (VDOT 10 to 90, finer steps at low values), and the browser interpolates it linearly.
  - The estimated finish on the run page uses `Vdot.time_for` at the Pace Trends distances: 5K (5,000 m), 10K (10,000 m), Half (21,097.5 m) and Marathon (42,195 m).
- **Pace zones (Phase 2, W1):** 37 fixed zones, shared by the performance index, the Pro Map's pace colouring and Training Bands' pace category, so a colour means the same thing everywhere. Zone 0 is "walk": below 5.5 km/h. Zones 1 to 35 are each 0.5 km/h wide, from 5.5 km/h up to 23.0 km/h, labelled with the pace at the zone's upper edge, seconds rounded down (zone 1 "10:00", zone 2 "9:13", zone 35 "2:36"). Zone 36 is "zoom": 23.0 km/h and up. The colour ramp runs from dark red (walk) through orange, yellow, green and blue to white (zoom), as CSS variables so light and dark can differ at the ends, and the top end stays visible on a card background.
- **Performance zone:** the pace at which the run's VDOT would run a 5K (`Vdot.time_for(5000, vdot)`, converted to km/h), looked up in the pace zones. Smashrun built its SPI zones the same way, from the SPI of a 5K at each speed.
- **Performance strip range:** the strip shows only part of the 37 zones. Take the performance zone of every run that has a VDOT; the range runs from the zone of the 25th-percentile VDOT (index `floor((n − 1) × 0.25)` in the sorted list) minus 1 zone, to the zone of the best VDOT plus 1 zone and clamped to 0 to 36, then widened to include this run's own zone. Each zone keeps its global colour, so a colour still means the same everywhere. A history of one run gives three zones around it.
- **Hill difficulty:** an integer from 1 to 5, nil without elevation gain. 1 when the run climbs under 1.5 m per km, otherwise 1 plus one step per 8 m per km (rounded up), capped at 5. Smashrun's own formula is not public; this was fitted against 16 public Smashrun ratings (15 match).
- **Rank histograms:** the cohort is all runs (distance) or the runs within ±10% of this run's distance (pace). Bins are equal-width over the 2nd to the 98th percentile, at most 12; both edges trim the same number of runs, `round(0.02 × (n − 1))`, so trimming starts at 26 runs; values beyond the domain fold into the first or last bin, which is labelled open-ended only when something folded in. Smaller cohorts, and cohorts where every value is equal, use the full range as one or a few bins. Ranks use the true values.
- **PRs (Smashrun rule):**
  - For benchmark D, qualifying runs have D ≤ distance < D + 1 km.
  - PR time = `timer_s × D / distance` (time interpolated at constant pace).
  - Bucket count = number of qualifying runs.
  - A PR is "official" when the Garmin event type is `race`.
- **Streak and break:**
  - A streak is maximal consecutive local dates with ≥ 1 run.
  - A break is maximal consecutive dates without a run, between the first run and the end of the period.
- **Trailing N days:** for each date, the sum of distance over `[date − N + 1, date]`.
- **Top runs (Pace Trends):** a run is a top run if its VDOT ranks ≤ 3 among runs in `[date − 29 days, date]`. Smashrun's FAQ says "3 best per month" while their blog says "rolling 30-day"; we use the rolling 30-day window (§13).
- **Regression:**
  - OLS of VDOT against time (days) over the top runs in the window.
  - The band is ±1 SD of the residuals.
  - Weekly change = slope × 7.
- **Pace axes:** linear in speed, labeled as pace. This matches Smashrun's 4:17 / 5:00 / 6:00 / 7:30 / 10:00 / 15:00 / 30:00 axis.
- **Pace variability:** distance covered in consecutive complete 10 s windows while the timer is running (stops count, the final partial window doesn't, and at least two windows are needed), then mean absolute deviation ÷ mean, as a %. The windows use linear interpolation between samples, so sparse recordings can hide changes. The percentage is stored on the run; the wheel is drawn separately from the 100 m bars, each a wedge whose radius is its |speed − mean| ÷ mean plus 0.25.
- **Runs in the prior 90 days:** the window is `[local midnight of the run's day − 90 days, the run's start)`. The mean is over previous runs that have the metric (a zero or missing HR counts as missing). Brush readouts: share = brushed runs ÷ previous runs; hours = Σ `timer_s`; distance = Σ `distance_m`; count. A brush selects values inside its range, edges included.
- **Elevation change bins:** computed from the full-resolution recording before the 2,000-point downsampling. Per 100 m bin, gain and loss are summed with the same 1 m hysteresis as the splits. The turning point carries across bin and km boundaries, and a change is attributed to the segment where it passes the threshold, split by distance when that segment spans bins. A missing altitude resets the turning point and marks its bins as missing. The per-km splits' gain and loss are sums of the same bins. Totals come from the recording and can differ from Garmin's summary.
- **Tracks:**
  - Garmin originals are untrimmed: Garmin applies trims only to the summary. FIT recordings are clipped: records before `started_at` (−2 s) are dropped, then records whose timer time exceeds `timer_s` (+2 s). Clipping to `elapsed_s` cut real data off runs with long pauses, because Garmin's `elapsed_s` can be shorter than the file's wall-clock span. Every FIT track is within 1% of its summary's distance and timer.
  - TCX isn't clipped, because the TCX parser keeps no per-row timestamps. It removes pauses per lap instead: the lap's excess (the time the lap adds to `t`, namely its own gaps plus the gap into its first trackpoint unless that is over 10 s, minus `TotalTimeSeconds`) is taken out of stall gaps (over 10 s, distance advancing under 0.5 m/s), largest first. Garmin's `timer_s` for these imports equals the sum of the laps' `TotalTimeSeconds`; 57 of the 64 TCX runs end within 0.5% of it.
  - `t` is timer seconds with pauses removed, `d` is cumulative metres, and cadence is steps/min for both legs.
  - If the distance series is missing or more than 10% off `distance_m`, `d` is rebuilt at constant pace, and `splits` and `pace_variability` stay nil. The run page omits the speed chart for those runs.
  - Zero cadence and zero heart rate count as missing for every format, because recordings carry cadence 0 while stopped (1,741 such points in the 18 sampled FIT and TCX runs).
  - Smashrun's no-GPS marker (`latitude` = `longitude` = −1.0; 1,588 points in 80 of 352 details) becomes a missing position, so route lines don't shoot out to (−1, −1).
  - Smashrun `clock` includes stopped time. The excess of `t` over the row's `timer_s` is removed from stopped intervals (distance advancing under 0.5 m/s), largest first and never more than the excess, with final `d` unchanged. This takes tracks within 2% of `timer_s` from 269 to 332 of 352, and tracks over 15% past it from 31 to 1. `timer_s` is the budget rather than the detail's `duration`, which was the worse match in 54 of the 63 runs where the two differ by over 2%.
  - Per-split elevation gain and loss use a 1 m hysteresis, which is close to Garmin's totals across the sampled runs (single runs are off by up to about 28 m).
  - `Track#bars(100)` gives the 100 m bars of the speed chart and the wheel; `Track#route` and `Track#route_distances` are parallel lists for the map and its cursor marker.
- **Notables:**
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
  - Windows: 1, 3, 6 and 12 months, and ever.
- **Food equivalents:** a static list of foods with kcal (`Food::ITEMS`), from a banana up to a kremšnita and a pizza. `Food.for(calories)` picks the food whose multiple (1 to 12) best matches the run's Garmin or Smashrun calories.
- **HR zones (Phase 3):** five zones from the boundaries on the profile (§5.6). Time in zone for a run is Garmin's `hrTimeInZone_1` to `hrTimeInZone_5` from its stored summary, in seconds. The per-zone bpm range is `HrZones#range(zone)`; `HrZones#bands` (floor and next floor, open at the top) feeds the HR chart's zone bands.
- **7-day average (Phase 3):** the mean of the values in the 7 calendar days ending on the day, shown only when that window holds at least 4 values and the day has a value of its own, so a gap in the readings is a gap in the line; missing days inside the window are skipped, not counted as zero.
- **Weight trend (Phase 3):** a 30-day centred moving average of the daily weight (the day's latest weigh-in). Unlike the 7-day average it bridges gaps between weigh-ins, however long (days the window can't reach are interpolated in a straight line between the neighbouring trend values), but draws nothing before the first or after the last one.
- **Gear stats (Phase 3):** distance = Σ `distance_m` and time = Σ `timer_s` of the runs with that gear; "last 12 months" = runs in the 365 days ending on the latest run's date; last used = the latest `local_started_at`. The suggested gear for a run with none is the gear used on most runs in the 14 days either side.

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

| Endpoint | Used for | Phase | Status |
|---|---|---|---|
| `GET /activitylist-service/activities/search/activities?activityType=running&start&limit` | All run summaries (paged, page size 100) | 0 | Verified |
| `GET /userprofile-service/userprofile/settings` | Profile settings | 0 | Verified |
| `GET /download-service/files/activity/{id}` | Original file as a ZIP: one `.fit` (watch runs) or one `.tcx` (2017 bulk imports). Untrimmed, so FIT recordings are clipped (§6). | 2 | Verified |
| `GET /biometric-service/heartRateZones/v2` | HR zone boundaries and max HR: an array with one entry per sport (`sport`, `zone1Floor` to `zone5Floor`, `maxHeartRateUsed`, `restingHeartRateUsed`, `lactateThresholdHeartRateUsed`, `trainingMethod`) | 3 | Verified (`/v2`; the bare path and `/all` are 404) |
| `GET /userprofile-service/socialProfile` | Display name | 3 | Not available (404). Not needed: the paths below work without a display name, and the `{displayName}` forms are 404 |
| `GET /usersummary-service/usersummary/daily?calendarDate=` | One day: `restingHeartRate`, `lastSevenDaysAvgRestingHeartRate`, `min/maxHeartRate`, `averageStressLevel`, `bodyBatteryHighestValue`, `bodyBatteryLowestValue`, `bodyBatteryAtWakeTime`, `bodyBatteryDuringSleep`, intensity minutes, steps, SpO2 and respiration | 3 | Verified (corrected path: without `/{displayName}`, which is 404). A day with no data returns 200 with null fields |
| `GET /usersummary-service/stats/stress/daily/{start}/{end}` | Stress (range): array of `calendarDate` and `values` (`overallStressLevel` and the rest, low, medium and high durations) | 3 | Verified. `/wellness-service/wellness/dailyStress/{date}` is 404 |
| `GET /wellness-service/wellness/dailyHeartRate?date=` | Resting HR, 7-day average and the day's heart rate samples | 3 | Verified (corrected path: without `/{displayName}`, which is 404). The daily summary above is the cheaper source |
| `GET /wellness-service/wellness/bodyBattery/reports/daily?startDate&endDate` | Body Battery (range): per day `charged`, `drained`, the value series and activity events | 3 | Verified |
| `GET /hrv-service/hrv/{date}` and `/hrv-service/hrv/daily/{from}/{to}` | HRV: `hrvSummary` (`lastNightAvg`, `weeklyAvg`, `lastNight5MinHigh`, `status`, `baseline` with `lowUpper`, `balancedLow`, `balancedUpper`) plus 5-minute readings; the range form returns `hrvSummaries` | 3 | Verified (both). A date with no data is 204 with an empty body. The range form accepted 30 and 90 days in one request |
| `GET /sleep-service/sleep/dailySleepData?date=` | Sleep duration, stages, score | 3 | Not available (404; also `/wellness-service/wellness/dailySleepData` with and without `/{displayName}`, and `/sleep-service/stats/sleep/daily/{start}/{end}`). The documented paths below work |
| `GET /sleep-service/sleep/dailySleep?date=` | One night, flat: `sleepTimeSeconds`, `deepSleepSeconds`, `lightSleepSeconds`, `remSleepSeconds`, `awakeSleepSeconds`, `napTimeSeconds`, sleep start and end (epoch ms, GMT and local), `averageSpO2Value`, `lowestSpO2Value`, `highestSpO2Value`, `averageRespirationValue`, `lowestRespirationValue`, `highestRespirationValue`, `avgSleepStress`, `avgHeartRate`, `awakeCount`, `sleepScores` (`overall.value` and a qualifier for each of total duration, stress, awake count, REM, light, deep, restlessness), `sleepNeed`, `sleepAlignment` | 3 | Verified (found from Garmin's swagger docs). A night with no data is 200 with null fields |
| `GET /sleep-service/sleep/dailySleepSummariesByDate?startDate&endDate` | The same night objects as an array, one per date (31 days in one request; the shape has `breathingDisruptionSeverity` in addition) | 3 | Verified. Empty before the first night: an empty array |
| `GET /usersummary-service/v2/dailysummaries?startDate&endDate` | `{data: [...]}`, one entry per day, in groups: `wellnessChronology`, `movement`, `calories`, `heartRate` (`minValue`, `maxValue`, `restingValue`), `intensityMinutes`, `stress` (`avgLevel`, `maxLevel`, proportions and durations), `bodyBattery` (`minValue`, `maxValue`, `chargedValue`, `drainedValue`, `latestValue`, feedback events), `hydration`, `respiration` (`avgValue`, `maxValue`, `minValue`, `latestValue`), `pulseOx` (`avgValue`, `minValue`, `latestValue`), `jetLag` | 3 | Verified. 31, 90 and 180 days in one request return one entry per day; 365 days is HTTP 500 (retried five times, still 500). No 7-day resting HR average and no Body Battery at wake time |
| `GET /activity-service/activity/{id}` | One run's detail: `summaryDTO` (the summary fields plus `beginPotentialStamina`, `endPotentialStamina`, `minAvailableStamina`, `avgGradeAdjustedSpeed`, `impactLoad`, `differenceBodyBattery`), `splitSummaries` and `metadataDTO` | 3 | Verified. `splitSummaries` is a handful of entries by `splitType` (4 on the sampled run), not one per kilometre, with no recovery heart rate. No `recoveryHeartRate` key anywhere in the detail |
| `GET /weight-service/weight/range/{start}/{end}?includeAll=true` | Weight: `dailyWeightSummaries` (one per weigh-in day), plus body fat, water, bone and muscle mass when the scale recorded them | 3 | Verified. `/weight-service/weight/dateRange` is 404. Weights are in grams |
| `GET /metrics-service/metrics/trainingreadiness/{date}` | Training readiness, recovery time | 3 | Not available (404) |
| `GET /metrics-service/metrics/trainingstatus/daily/{date}` | Training status and load | 3 | Not available (404, and `/aggregated/{date}` too) |
| `GET /metrics-service/metrics/maxmet/daily/{start}/{end}` | VO2max by day | 3 | Not available (404, and `/maxmet/latest/{date}` too). The run summaries have no VO2max either (no `vO2MaxValue` on any of 2,869 runs), so VO2max is not in the Personal API data and is not shown |

The probe (`bin/rails garmin:probe`, W6, run on 27 Oct 2026) tried these paths against the real API with yesterday, a date a year ago and the first run's date. The Personal API takes no display name in the wellness paths: the `/{displayName}` forms are 404 and the name-less ones work. Dates with no data are a 200 with null fields (or a 204 for HRV, or an empty array for stress). Earliest data, found by bisecting (a day or window with data, not a gap-free guarantee):

| Metric | Earliest data |
|---|---|
| Resting HR, stress, Body Battery | between mid-2017 and early 2018 (the stored daily summaries start 2017-05-09, stress and Body Battery from 2017-09-22) |
| Weight | mid-2017 |
| HRV | late 2022 |
| Sleep time | 2017-05-10 |
| Sleep stages | by early 2018 (2017-09 has none, 2018-03 has all) |
| Sleep score | between March 2021 and March 2022 (none in 2021-03, all in 2022-03) |
| Overnight respiration and SpO2 | by early 2020 (none in 2019-03, all in 2020-03) |
| v2 daily summaries | 2017-05 (within 32 days of 2017-05-23) |

The probe bisects with a few requests per metric, so each date is only good to a few months; the backfill stops a metric after several empty weeks (R11) and doesn't depend on them. The probe's output (statuses and JSON key shapes, no values) is in `/tmp/opencode/p5/probe.txt`.

A second round (27 Oct 2026, after reading Garmin's Personal API swagger docs, `bin/rails garmin:probe`, 30 requests) found sleep under `/sleep-service/sleep/dailySleep` and `dailySleepSummariesByDate`, which round one had missed by guessing the Connect web path `dailySleepData`. Against the stored daily summaries, `v2/dailysummaries` matched on resting HR, average stress and Body Battery high and low for all 5 recent days compared. It has no `lastSevenDaysAvgRestingHeartRate` and no at-wake Body Battery, so it can't replace the daily summary without losing two stored columns. The activity-detail run carries no recovery heart rate. Its output is in `/tmp/opencode/p8/probe.txt`.

The Personal API has **no** time-series, laps or weather endpoints, and its only split data is the `splitSummaries` groups in the activity detail. Everything per-second comes from the original file, or from Smashrun for the years before Garmin (§7.5), and weather comes from Open-Meteo. The activity summaries do carry, per run, the time in each HR zone, training effect, training load, Body Battery change, intensity minutes and running dynamics.

### 7.2 Sync flow

- **Backfill:** page through the activity search newest to oldest until a page comes back empty, upserting by `(source, external_id)`. About 30 requests cover the whole history.
- **Incremental:** page newest-first until a full page is all already-known IDs.
- **Full resync:** a rare manual action. It re-pages everything, picks up edits to old activities, and deletes local Garmin runs that no longer exist on Garmin.
- **Triggers:** the hourly `garmin_sync` recurring task (`config/recurring.yml`, production) and the **Sync now** button. Both run `Activity::SyncJob` → `Activity.sync_now` (the button through `Activity.sync_later`). In development `bin/dev` syncs only on the button, with the default job adapter; the sync is idempotent. After a successful sync the Strava link job queues a recent pass (§7.6).
- **Originals:**
  - `bin/rails activities:download` is the one-time backfill: about 2,514 files at ≤ 1 request/s (about 45 min of downloads), in the foreground with progress output. FIT parsing is slower than the download (2 to 8 s per file), so the whole run takes hours single-process. The class methods respect relation scoping, so split it across processes, for example `Activity.where("activities.id % 4 = ?", k).download_originals` in 4 `bin/rails runner` processes. Each process throttles itself to 1 request/s, so together they exceed 1 request/s: the real backfill averaged about 1.6 requests/s with 4 processes and saw no errors.
  - The sync downloads the original of every run it pages through that has none, processes a run that has an original but no track, and reprocesses a run whose `started_at`, `timer_s` or `distance_m` changed, which picks up trims. A failure for one run is logged and skipped, and the next sync retries it. The sync refreshes `sync_started_at` after each run, so a long sync keeps counting as running.
  - `bin/rails activities:reprocess` rebuilds all derived data from stored originals whenever the algorithms change.
- **Weather:** each sync also fetches weather for every run up to 60 days old that still has none: from the forecast API for the last 5 days (§7.4), from the archive for older runs. `bin/rails weather:fetch` is the full backfill.
- **Wellness (built, W7):** a separate hourly recurring job (`wellness_sync`, `Wellness::SyncJob` → `Wellness::Sync#refresh`, at minute 30), so a wellness failure never blocks run syncing. It refreshes today and the last 3 days, because Garmin fills in late data, plus the HR zones, and sets `profiles.wellness_synced_at`. Three sources: the daily summary per day (resting HR and its 7-day average, stress, Body Battery high, low and at wake; it covers what the stress and Body Battery range endpoints carry, so those two are not called), and the HRV and weight range forms. `bin/rails wellness:backfill` (`DAYS=n` limits it) is the one-time backfill from the first run date onward: throttled to 1 request/s, newest first, idempotent upserts by date, in 30-day chunks (the summary does its 30 days one request each), resumable (days whose summary is stored are skipped, and so are days marked empty at least 7 days after their date; a younger marker, written by the hourly refresh before the watch synced, is fetched again). A source stops after 6 consecutive chunks with no data days, stored or fetched (R11); a chunk skipped because it is stored counts by what it holds. It prints counts only. The 30-day dry run on the dev database: 34 requests, 30 days of every metric, 21 weigh-in days, HR zones from Garmin.

### 7.3 Strava gap fill (Phase 0, one-time)

`bin/rails strava:fetch` is the source: it uses the connected Strava account (§7.6), pages through `/athlete/activities`, and applies the cutoff below. The API gives each run's real local time and its race flag. `start_date` is UTC and `start_date_local` is wall-clock time with a `Z` suffix, so both are parsed as UTC. The archive import stays as a fallback: request the archive from Strava (*Settings → My Account → Download or Delete Your Account → Request your archive*), unzip it, and run `bin/rails strava:import[~/Downloads/export_xxx]`, which reads `activities.csv` and takes rows whose type matches `/run/i`.

1. **Cutoff:** Garmin is authoritative from its first run on. Rows that start later than 10 minutes before the first Garmin run are skipped, so sync Garmin first; the tasks refuse to run without Garmin runs. Matching each Strava run against Garmin runs was tried first, but every Strava-only "run" inside Garmin's history turned out to be a hike Garmin recorded as hiking (78) or a second copy of a run (1). The task prints a report of imported and skipped rows.
2. Imported runs get `source: "strava"` and link out to Strava.
3. Tracks come from Smashrun (§7.5).

### 7.4 Weather (Phase 2)

- Source: the Open-Meteo historical archive API (free, no key) for runs older than 5 days, and the forecast API (`https://api.open-meteo.com/v1/forecast`, same variables, `start_date` and `end_date`, which serves the recent past) for runs from the last 5 days, so yesterday's run has weather. A stored value is never refetched from the archive.
- Fetch hourly temperature, humidity, wind and precipitation at the run's local midpoint hour, plus the daily sunrise and sunset, with `timezone=auto`.
- Coordinates are rounded to 0.01° before sending.
- Results are cached on the activity.
- Treadmill and indoor runs, and runs without start coordinates, get no weather.
- The archive was seen to lag about 5 days, so the 5-day cut-off (`Activity::Weather::ARCHIVE_LAG`) stays even though a live check on 2026-10-27 found the archive already returned values for today. When either API returns nulls, `weather` stays nil and a later sync retries it (§7.2).

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

### 7.6 Strava connection, run links and gear (Phase 2 built; gear is Phase 3)

- **Connection:** the nav's Connect Strava button (shown only while disconnected) starts Strava's OAuth with a session `state`. The callback is `GET /strava/callback` on whichever host serves the app (`http://localhost:3000` locally, `https://run.rekar.eu` in production). It checks the state and that the grant includes activity access (otherwise it shows a fixed alert and stores nothing), then stores the access token, refresh token and expiry on the singleton `Profile` (both tokens encrypted with Active Record encryption), shows a notice and queues a full link. The Connect button's form has `data-turbo=false`, because Turbo's fetch can't follow the cross-origin redirect to Strava.
- **Scope:** `activity:read_all,profile:read_all` (the latter Strava requires for the gear endpoints, built in W11). A grant without activity access is still rejected. The pre-W11 connection has only the old scope, so `profiles.strava_scope` records the scope the callback granted, and until it includes gear access the nav shows **Reconnect Strava** and gear features wait (not an error). Reconnecting is an owner action after the W11 deploy.
- **Refresh:** `Strava::Client` refreshes when the token expires within 5 minutes and saves the rotated refresh token. The refresh request is made outside any transaction; if Strava rejects it but the stored refresh token is no longer the one sent, another process rotated it, so the new token is used. A 401 or a revoked refresh clears the connection so the button shows again. Requests use 10 s open and read timeouts, and there are no retries. Strava's limits are 100 requests per 15 minutes and 1,000 per day.
- **Links:** `activities.strava_id` is matched to the run whose `started_at` is within ±10 minutes of the Strava run's start, nearest first, and is never overwritten or reused. The connect queues a full scan (about 15 requests at 200 per page); each Garmin sync then links recent unlinked runs from the newest activities only. The Strava `external_id` field (upload file name, or `garmin_push_N`) is not used.
- **Gear (W11):**
  - The same scans read each activity's `gear_id` (the summary representation includes it; null means no gear set) into `activities.strava_gear_id` for every run linked by `strava_id`, including the pre-Garmin Strava rows.
  - Each distinct `gear_id` gets one `GET /gear/{id}` (name, brand, model, description, distance), refreshed weekly, plus `GET /athlete` for its shoe list. The raw payload is stored in `gears.summary`, so fields can be re-derived without refetching; the `retired` flag is read from it when Strava exposes it (unverified, §13).
  - Passes: a full scan on connect and on the Gear page's Refresh button; an hourly recent pass over the last 30 days (one request) so a gear fixed on Strava shows up soon, run in the same job as the link pass (one job refreshes the token at a time). `profiles.strava_gear_synced_at` is set when a full pass finishes; until then the Gear page says the first scan is pending, the hourly pass is the full one, and no run shows a gear tag or an amber No gear. Failed full passes (any Strava error except a disconnect, and network timeouts) are counted in `profiles.strava_gear_attempts`; after 2 the hourly pass goes back to the recent one (otherwise a gear that always fails would cost about 500 requests a day against the 1,000 limit), the Gear page says the first scan failed and points to Refresh from Strava, which always runs. A successful full pass and a reconnect reset the count. A Strava error in the gear step of a link job is logged by class and does not fail the job. A run's gear can only change on the next hourly scan if it is within 30 days; older runs change on Refresh from Strava.
  - Gear is read-only: there are no write calls to Strava.

## 8. Data model (SQLite)

### `activities` (Phase 0)

| Column | Notes |
|---|---|
| `source` | `garmin`, `strava` or `smashrun`. Unique with `external_id`. |
| `external_id` | Garmin, Strava or Smashrun activity ID. |
| `strava_id` | Nullable, indexed. The Strava activity ID behind the Open in Strava button: set from `external_id` for Strava-sourced runs and by the link job for the others (§7.6). |
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
| `vdot` | Computed on save |
| `summary` | JSON: the raw Garmin summary or Strava CSV row, so fields can be re-derived without re-fetching (HR zone times, training effect and load, Body Battery change and running dynamics are read from here). |

Index on `local_started_at`. All of history is about 2,900 rows. Aggregations load the period's runs into Ruby; add caching only if measurements show a need.

### Phase 2 additions (built)

- On `activities`: `has_one_attached :original` (Active Storage, local disk). Columns `splits` (JSON, per km), `pace_variability` (float), `weather` (JSON: temperature, humidity, wind, precipitation, code, sunrise, sunset). The original is the Garmin ZIP as downloaded (`<id>.zip`) or the gzipped Smashrun detail (`smashrun-<id>.json.gz`).
- `profiles` holds the Strava connection: `strava_access_token` and `strava_refresh_token` (encrypted) and `strava_token_expires_at` (§7.6).
- `tracks`: `activity_id` (unique), `chart_metrics` (nullable JSON: `elevation`, the 100 m gain/loss bins; older rows may still hold an unused `speed_windows`; nil for rebuilt distances or not yet processed) and `data` (JSON of columnar arrays `t, d, lat, lng, alt, hr, cad`, downsampled to ≤ 2,000 points; series without data are omitted). Tracks live in a separate table so loading activities stays lean.
- No `notables` column: notables are computed on the fly.

### Phase 3 additions (planned)

- `profiles`: `hr_zones` (JSON: boundaries, max HR, and whether they came from Garmin or the default bands), `strava_scope` (string), `strava_gear_synced_at` (datetime), `strava_gear_attempts` (integer, failed full gear passes, default 0), `wellness_synced_at` (datetime).
- `wellness_days` (built, W7): `date` (unique), `resting_hr`, `resting_hr_avg_7d` (Garmin's 7-day average), `hrv_last_night`, `hrv_weekly_avg`, `hrv_baseline_low`, `hrv_baseline_high`, `hrv_status`, `body_battery_high`, `body_battery_low`, `body_battery_wake`, `stress_avg`, `weight_kg` (the day's latest weigh-in, converted from grams), the night that ended that morning (`sleep_s`, `sleep_deep_s`, `sleep_light_s`, `sleep_rem_s`, `sleep_awake_s`, `sleep_score`, `sleep_hr_avg`, `sleep_stress_avg`, from `sleepTimeSeconds`, the stage seconds, `sleepScores.overall.value`, `avgHeartRate` and `avgSleepStress` of `dailySleepSummariesByDate`; overnight SpO2 and respiration are in the payload but have no columns or charts, dropped by the owner as not useful), and `raw` (JSON keyed `summary`, `hrv`, `weight` and `sleep`, the day's payload from each endpoint). A day Garmin answered with no summary data gets a row with null columns and `raw["summary"]` = `{}`, so the backfill doesn't ask again (a refresh does); null fields never overwrite stored values or payloads. The wellness columns and `raw` are in `config.filter_parameters`, so SQL binds show `[FILTERED]` in the logs. Finalised by the W6 probe: training readiness has no endpoint, so it has no columns; sleep was added after the second probe round.
- `gears`: `strava_id` (string, unique), `name`, `brand_name`, `model` (Strava's `model_name`; Active Record reserves `model_name` as an attribute name), `retired` (boolean, default false), `summary` (JSON, the raw Strava payload), `synced_at`.
- `activities.strava_gear_id` (string, nullable, indexed): the Strava gear ID as read; matched to `gears.strava_id` by value, so activities can be read before their gear row exists.

### Phase 4 additions (planned)

- `activities.bands` (built, W15): JSON `{"pace": [37 seconds], "hr": [5], "grade": [7]}` of whole seconds per pace zone, HR zone (zone 1 first) and grade bucket (steepest descent first), computed from the stored track (§5.9). An array whose total is 0 (no HR, no altitude) is nil, and the whole column is nil for rebuilt distances and runs without a track. HR bands use the zones in force when they were computed.
- `goals`: `period` (month or year), `starts_on`, `distance_m`.

### Singleton `profile`

Garmin profile settings (JSON), HR zones (Phase 3), `synced_at`, `sync_started_at`, `sync_error`, and the Strava connection.

## 9. Architecture and stack

- **Generator (Phase 0):**

  ```
  rails new . --name=smashback --css=tailwind --skip-kamal --skip-thruster --skip-docker --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-jbuilder --skip-system-test
  ```

  This keeps the Rails defaults: SQLite, Importmap, Propshaft, Hotwire, Solid Cache/Queue/Cable, RuboCop omakase, Brakeman, `bin/ci`.
- **Gems:**
  - `dotenv`: Rails doesn't load `.env` on its own.
  - Tests: `factory_bot_rails`, `webmock` (as in Visualizer).
  - `rubyzip` (Garmin downloads are ZIPs) and `fit4ruby` from your fork `miharekar/fit4ruby` (§3). Nokogiri, already bundled, parses TCX.
  - `csv` for the Strava import.
- **JS (Importmap only, no Node build):**
  - d3 pinned with `bin/importmap pin`.
  - Mapbox GL JS, the single-file UMD build vendored in `vendor/javascript` with its CSS (`app/assets/stylesheets/mapbox-gl.css`), pinned with `preload: false` and imported dynamically so only run pages with a map load it. The multi-chunk ESM build breaks under Propshaft's digested paths. Every map, including the Phase 4 Pro Map, uses it.
- **Code organization (Visualizer `STYLE.md`):**
  - Rich models with thin controllers.
  - Class-scoped concerns, for example `Activity::Performance` for VDOT and hill difficulty, `Activity::GarminSync`, `Activity::StravaImport`, `Activity::StravaLink`.
  - POROs in `app/models` for aggregates: `Overview`, `PersonalRecords`, `PaceTrend`, `PrProgress`; and, as they arrive, `HrZones` and `PaceZones`.
  - Integrations in `app/lib`: `Garmin::Client`, `Strava::Client`, `Smashrun::Client`, `OpenMeteo::Client`.
  - Jobs follow the `_later`/`_now` pattern.
  - View constants for cards, type and controls live in helpers (`WidgetsHelper` and `ControlsHelper`, §10).
- **Routes:** REST resources only:
  - Built: `resource :overview` (with `:year`/`:month`), `resource :pace_trend`, `resource :pr_progress`, `resource :wellness` (show, with `from` and `to`), `resources :runs` (index and show), `resource :sync` (`create` = Sync now), `resource :theme` (`update`), `resource :strava_connection` and the OAuth callback.
  - Phase 3: `resources :gears` (index, served at `/gear`), `resource :gear_sync` (`create` = Refresh from Strava), and a `gear` filter param on `/runs`.
  - Phase 4: `runs/:run_id/map` (`resource :map`, show, built), `resource :training_bands` (show, built), `resources :goals`.
- **Charts:**
  - One Stimulus controller per chart type (kebab-case files in `app/javascript/controllers`): `period-bars`, `trailing-line`, `pace-scatter`, `heatmap`, `streaks`, `pace-trends`, `pr-progress`, `run-speed`, `run-profiles`, `run-map`, `wellness`, `training-bands`, `pace-variability`, `elevation-profile`, `rank-distribution`, `analyze-run`, `day-tip`, `info`, and so on.
  - The server renders chart data as JSON into Stimulus values, so no JSON endpoints are needed.
  - Shared helpers live in `app/javascript/helpers/`: formatters, tooltip (`tooltipHtml`), resize, time, regression, `linked_selection` (Overview hover), `run_cursor` (run page distance cursor, and the Wellness day cursor) and `route_point`, `wellness` (moving means, zone stacking, step windows), `training_bands` (week stacking, filters, tooltip rows), roving focus, and the pure logic of each chart.
  - Charts redraw on `ResizeObserver`.
  - Theme comes from CSS variables (`--chart-accent`, `--chart-muted`, `--chart-grid`, …), so a light/dark switch needs no redraw. The variables, Tailwind's `dark:` variant and `color-scheme` all key off `<html data-theme>`.

### Deployment

- One Docker container (`docker compose up -d --build`, Dockerfile on `ruby:4.0.9-slim`, Puma without Thruster) on port 9295, served at `https://run.rekar.eu` by Caddy on the Pi over Tailscale. On the LAN it speaks plain http, so `force_ssl` and `assume_ssl` are off. Rails honours the forwarded scheme and host from any sender, so the Strava OAuth callback is `https://run.rekar.eu/strava/callback`; the tailnet range is a trusted proxy only so that `request.remote_ip` is the real client.
- The production primary database is the same `storage/development.sqlite3` that `bin/dev` uses (SQLite in WAL mode), so there is one dataset; cache, queue and cable have their own `storage/production_*.sqlite3`. `./storage` and `config/master.key` are mounted, and `.env` supplies the Garmin, Strava, Smashrun and Mapbox settings. The entrypoint runs `db:prepare` only. A migration run by the container marks the shared primary's environment as `production`; `bin/rails db:environment:set RAILS_ENV=development` undoes that for dev's protected tasks.
- Solid Queue runs inside Puma and runs the hourly Garmin sync (§7.2) and, in Phase 3, the wellness refresh. There is no auth: the machine is only reachable through the LAN and the tailnet (§11, R12).
- Rebuild the container after code or migration changes, and at every phase close-out.

## 10. Design

One design system, defined once in helpers (`WidgetsHelper` for cards and type, and `ControlsHelper`, introduced in W2 and completed in W4), so views never write these classes inline. Both helpers are plain constants plus a few view helpers (`page_header`, `empty_state`, `chip`, `button_group`, `segment`, `toggle_button`, `action_button`).

- **Theme:** System, Light or Dark, rendered as `<html data-theme>`. Tailwind's `dark:` variant, the `--chart-*` CSS variables and `color-scheme` all key off that attribute, so no chart redraws on a switch. Chart colours are always CSS variables, never `light-dark()`, because the map reads them with `getComputedStyle`.
- **Palette:**
  - Accent is a nod to Smashrun's "Team Yellow Green": lime/green (dark mode base `#6ACD12`, highlight `#9CFF44`, low `#254806`; deeper greens in light mode).
  - Amber for highlighted runs, "this run", predictions and the linked-hover selection.
  - Neutrals from Tailwind `zinc`.
  - Pace zones use one shared ramp (§6) defined as CSS variables.
- **Layout:** `max-w-7xl`. Every page is a header row (`page_header`: the title and its ⓘ on the left, actions on the right, wrapping), then the period or window selectors as button groups (`mt-4`), then the content (`mt-6`), whose cards sit `gap-4` apart. A page or list with nothing to show uses one empty state (`empty_state`: a bordered block with a title and an optional link). Two columns on desktop, one on narrow screens. Nothing scrolls sideways at 360 px.
- **Cards:** one card style (`CARD`; margins stay at the call site). A card's title row (`CARD_HEADER`) has the title (`CARD_TITLE`) and its ⓘ on the left and the chart's button group on the right, wrapping on narrow screens; the chart follows at `mt-3`. A metric switch shows its selection in the title text ("Distance per month"), never as a dropdown.
- **Type:** the system UI font stack. Page title `text-2xl` semibold; card title semibold; tile label small, medium, muted (`TILE_LABEL`); tile value `text-4xl` semibold with `tabular-nums` (`TILE_VALUE`), the lime accent only on the headline numbers (`ACCENT`); units and sub-lines small and muted (`TILE_UNIT`, `TILE_SUB`); hints `text-xs` muted (`HINT`, which sets type and colour only; each call site sets its margin) and legends (`LEGEND`: a marker, then its label, left to right); muted text everywhere is `MUTED`, text links are `LINK`, empty values `PLACEHOLDER`. Tables use `TABLE`, `TABLE_HEAD`, `TABLE_BODY`, `TABLE_ROW`, `CELL` (`px-3 py-2`) and `TABLE_LINK`; tags on a run or record are `chip`. Long explanations go in the ⓘ; a hint stays only to say how to use the chart.
- **Controls:** four kinds, three of them in `ControlsHelper` (`action_button` and `BUTTON`, `button_group` with `segment`, `toggle_button`), sharing height, radius, focus ring and disabled style:
  - **Button:** an outlined action or link (Sync now, Open in Strava, Previous, Latest run).
  - **Button group (segmented control):** a single choice among options (metric, window, mode, distance, period; the theme switch is one with icon segments). `aria-pressed` buttons in one track, or links when the choice is a page; the selected segment has one accent look everywhere. It replaces every `<select>`.
  - **Toggle button:** an independent on/off filter (Exclude pauses, a gear in a chart), drawn like one selected segment.
  - **Icon button:** the ⓘ (`ControlsHelper::INFO`) and the icon segments of the theme switch (`ICON_SEGMENT`).
  - **Focus ring:** one global `a`/`button` `:focus-visible` rule in `application.css` (2 px, the chart accent, 2 px offset); no control writes its own.
- **Tooltips:** the shared tooltip. Title-and-rows tooltips are built with `tooltipHtml` (a muted title, then label/value rows), everything escaped; distances to one decimal.
- **Motion:** 150 to 250 ms transitions on chart updates. The one longer motion is the dot glide in "Runs in the prior 90 days" (about 400 ms).
- **Accessibility:** keyboard operable charts (§5.1), visible `:focus-visible` rings, labelled controls, and text contrast in both themes.

## 11. Privacy and security

- **Data sensitivity:** the app stores GPS tracks, which reveal home and routines, plus heart-rate data, and from Phase 3 health data (HRV, weight, Body Battery, stress). It is your own data, kept on your machine. Health values are never logged or printed, and test fixtures are synthetic.
- **Network exposure:** the container (port 9295) and the dev server (0.0.0.0:3000) are reachable on the LAN, and run.rekar.eu is served by Caddy on the Pi over Tailscale. There is no auth, so the tailnet and LAN are the boundary. run.rekar.eu is confirmed tailnet-only (2026-10-27). HTTP basic auth at Caddy stays an optional hardening (R12).
- **Secrets:** `.env` is ignored by Rails' default `.gitignore` (`/.env*`) and is mode 600.
- **Smashrun credentials:** `SMASHRUN_USERNAME` and `SMASHRUN_PASSWORD` grant full access to the Smashrun account. Never log them. The 12-week token is held only in memory.
- **Garmin key:** the key gives read access to all of your Garmin health data. It must never be logged; filter it and the bearer token out of logs and error output.
- **Strava tokens:** stored encrypted on the profile with Active Record encryption (keys in the credentials file, opened by `config/master.key`, which the container mounts read-only). Never log them or the OAuth `code`.
- **Key rotation:** create a new key at `connect.garmin.com/app/settings/personalApiToken`, update `.env`, and restart.
- **Storage:** `storage/` (SQLite databases and the stored originals) is git-ignored. `storage/dumps/` holds raw API dumps and captures from earlier phases: never print it or copy it into `test/`. If you back it up, encrypt the backup.
- **Design references:** other people's public Smashrun pages are read only to see their layout. Nothing from them is stored in the repo, logged or used as test data.
- **Third parties:**
  - Garmin (the source).
  - Strava (gap fill, run links, and from Phase 3 gear; read-only).
  - Smashrun (until it shuts down): receives your login, once per fetch.
  - Open-Meteo: receives rounded coordinates and dates.
  - Mapbox: receives the style, tile and font requests, which reveal which areas you view, and the public token. With `performanceMetricsCollection: false` (GL JS sends `gljs.performance` events with the user agent, screen size and GPU by default), the only events still sent to `events.mapbox.com` are `appUserTurnstile`, `style.load` and `map.load` (the one Mapbox bills on, one per map initialised on a page). They carry the SDK version, the style URL, the token-derived SKU token and an anonymous user ID that GL keeps in `localStorage` (keys starting `mapbox.eventData`).
  - No analytics.
- **Terms:** Garmin's Personal API is for personal use only. Turning this into a multi-user app would mean handling other people's health and location data. That would require Garmin's business developer program and real privacy and compliance work. It is out of scope.

## 12. Testing and acceptance

**Test suite**

- Minitest, FactoryBot, and WebMock with the network disabled. Minitest also covers the view helpers, for example the controls helper's button group, segment and toggle button.
- Fixtures are synthetic: made-up coordinates, names, IDs, heart rates and wellness values. Nothing downloaded from your accounts goes into `test/`.

**Unit tests**

- VDOT golden values, predictions (the Ruby lookup tables are interpolated in the browser), pace zones and the performance zone (boundaries at 5.5, 6.0 and 23.0 km/h, nil VDOT).
- PR bucketing and interpolation, streaks and breaks, trailing sums, weekly buckets, magic PR targets, top-run flagging.
- Garmin client: token caching, re-exchange on 401, expired-key error. Sync: idempotent upsert, delete reconciliation. Strava gap-fill cutoff.
- Track parsers (FIT, TCX with two `<Track>`s, Smashrun JSON) and metrics: splits, variability, elevation bins, clipping, cadence doubling, the 2,000-point cap, `route` and `route_distances` staying aligned when a GPS fix is missing.
- Smashrun import: cutoff, nearest match, creation, race OR, calorie fill. Weather, notables (one per type, moon phase on known dates), food picker.
- Strava connection and links: state check, scope check, refresh and rotation, revoked connection, ±10 minute matching. Hill difficulty (the fitted table and its edges).
- Phase 3: wellness parsers and sync (idempotent upserts, the 3-day refresh, chunking, missing metrics), HR zone lookup and the default bands, Strava gear sync (missing scope, gear without a row yet, null gear, `retired` absent, 401 handling), gear stats and the "no gear" and "suggested gear" rules.

**JS tests**

`node --test` for the pure logic of: regression, brush stats, formatters, tooltips (`tooltipHtml` escaping), run stats, linked selection, rank histograms, pace variability, the run cursor and route point lookup, the elevation profile, estimated-finish cycling, and the prior-90-days helpers (axes per metric, mean without nulls, brush selection, readout cycling, days-before labels, same-day grouping). Phase 3 adds the wellness chart helpers (7-day average, weight trend, zone bar maths; built in `wellness_test.mjs`).

**Golden values**

Smashback's values, next to smashrun.com/miharekar (all time, km), as of 2026-10-25. Smashrun used its own processing and counts about 470 km of hikes that Garmin recorded as hiking. Streaks and breaks must match exactly; totals and PRs within ±0.1%. Recompute when an aggregation changes.

| Metric | Smashback | Smashrun |
|---|---|---|
| Runs | 2,868 | 2,942 |
| Total distance | 32,974.3 km | ≈ 33,464 km |
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
- Brushing Pace Trends and PR Progress, and hovering the Overview charts, stays smooth: no handler over ~16 ms on ~2,900 runs.
- The Wellness page renders in under 300 ms server time on the full history, and its brush stays under ~16 ms per handler.

**Definition of done for every work item (§14)**

- `bin/rails test`, `node --test test/javascript/*_test.mjs`, `bin/rubocop`, `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`, `herb analyze .` and the Herb linter (`npx @herb-tools/linter app/views --simple --no-color`) pass.
- New logic has tests: Ruby for metrics and sync, `node --test` for interactive math.
- This document and `AGENTS.md` are updated in the same change.
- A browser check on the item's own dev server, in light and dark, at 1300 px and 360 px: no sideways scroll, a clean console (the Herb dev-tools messages aside), the keyboard path works, tooltips escape their text, and nothing lingers after a Turbo visit.
- No personal data in tests, logs or screenshots shared in reports.

## 13. Risks and open questions

| # | Item | Plan |
|---|---|---|
| R1 | FIT parsing in Ruby. | Spiked on 16 FIT files from 2018 to 2026: the fork parses all of them with its post-read `Activity#check` validation no-oped, matching Garmin's distance and timer. Later, with all runs processed, every FIT track is within 1% of its summary. `fit_kit` doesn't build on Ruby 4.0.9. About 2,000 records/s, so a full backfill needs several processes (§7.2). |
| R2 | Personal API rate limits are undocumented. The maximum `limit` is 100 (250 returns HTTP 500). | Verified: no 429s in a full backfill at 1 request/s. Throttle and back off anyway. |
| R3 | Does `activityType=running` include child types such as treadmill and trail? | Verified: it includes `trail_running`. Treadmill runs are typed `treadmill_running`. |
| R5 | Strava CSV quirks. | Moot: the Strava API is the primary source (§7.3). |
| R6 | Personal API key expiry (≤ 1 year). | Clear banner and rotation docs (§11). |
| R7 | Smashrun shutting down. | Its data is fetched once into stored originals (§7.5), so nothing depends on it afterwards. |
| R8 | Garmin originals are untrimmed. | Clip FIT recordings to `started_at` and `timer_s` of recording time (§6). |
| R9 | The Open-Meteo archive lags about 5 days. | Runs from the last 5 days use the forecast API; when either API returns nulls, leave `weather` nil and retry on later syncs (§7.2, §7.4). |
| R10 | The Personal API may not expose some wellness data. **Resolved by W6: training readiness, recovery time, training status and load, and VO2max by day are not available; resting HR, HRV, sleep (second probe round), stress, Body Battery, weight and HR zones are.** | The scope shrank to what exists. The summary-based fields (HR zone times, training effect and load, Body Battery change) need no endpoint. **Owner decision: anything that isn't available in the API we leave out.** Training readiness, recovery time, training status and VO2max (by day, and from the run summaries, which carry none) stay cut, and there is no Garmin data-export import. |
| R11 | Per-day endpoints make the wellness backfill long (about 3,500 days per metric). | 1 request/s, resumable, newest first, run in the background. Stop a metric after several empty weeks, because older devices didn't record it. |
| R12 | Health data will sit in an app with no login. | run.rekar.eu is confirmed tailnet-only (2026-10-27); keep it that way (basic auth at Caddy is optional hardening). Never log health values; synthetic fixtures. |
| R13 | Strava gear needs `profile:read_all`, which the stored connection lacks, and the `retired` flag is not confirmed in the API. | A reconnect prompt, with gear features waiting for the grant. The raw gear payload is stored so `retired` can be derived later. Until it is known, show every gear as active. |
| R14 | Strava rate limits (100 requests per 15 minutes, 1,000 per day). | A full link or gear scan is about 15 requests and the recent pass is 1 request an hour. The first gear scan is retried at most twice (§7.6). |
| Q1 | Smashrun Pro's "Trends Comparison": what did it do? | Unknown. Skipped unless you remember. |
| Q3 | Top runs: rolling 30-day window or calendar month? | Rolling 30-day chosen. It's a one-line change. |
| Q4 | Garmin Connect web URL for activities. | `/app/activity/:id`. |
| Q5 | Smashrun's estimated finish: how does it step? | The captured page and scripts hold no code for it, only a ▶ beside the distance. We step 5K, 10K, Half, Marathon and wrap. Tell us if the real widget does something else. |

## 14. Work queue and checklist

Work in this order. Items marked "parallel" touch different files and can run at the same time; the owner-visible results are in §5. Every item meets the definition of done in §12. Conventions are in `AGENTS.md`.

**Phase 0 and 1: done.** Phase 2 as listed in §5.5, Strava links, theme switch, linked hover and the container are built and committed.

### Phase 2: finishing

- [x] **W0: install this document and commit the pending cleanup.** Replace `docs/PRD.md` with this document. The working tree also holds a 7-file simplification: the route marker no longer hides across GPS gaps or before and after the first fix, the Analyze Run histogram axis no longer widens for this run's value (moot after W3), `noMouseFocus` is a one-liner, and the route/distance pairing test in `test/models/track_test.rb` is removed. Run the full checks, then commit. Restore the pairing test unless the owner removed it on purpose: it guards `route` and `route_distances` staying aligned when a GPS fix is missing.
- [x] **W1: performance index and estimated finish (§5.5, §6).** Add `PaceZones` (Ruby, with the colour ramp as CSS variables) and `Activity#performance_zone`; build the two-column card and its stepping controller; remove the VDOT tile's 2×2 grid; repack the tile grid. Parallel with W2. Done when: zone lookup tests cover the boundaries and nil VDOT, a node test covers the cycling order, a controller test covers the card, and the browser check covers all four distances, keyboard, and runs with and without HR, variability, altitude and VDOT.
- [x] **W2: buttons instead of dropdowns (§5.1, §10).** Introduce the controls helper with the button group, toggle button and button, and replace the four `<select>`s: Overview distance-per-period metric (5 options), the Overview scatter's y metric (3), Pace Trends' finish distance (4). Move the hand-rolled groups (PR Progress mode and reference period, Pace Trends presets, the speed chart's 100 m / per km toggle) and the Pace Trends filter chips onto the same components. Titles follow the selection; groups wrap at 360 px. Leave the Analyze Run select for W3. Parallel with W1. Done when: no `<select>` remains outside the Analyze Run view, behaviour and `aria-pressed` are unchanged, and tests are updated.
- [x] **W3: rebuild "Runs in the prior 90 days" (§5.5 item 8, §6).** Dot strip, brush with cycling readout, day timeline, legend, keyboard and tooltips as specified, using the W2 button group. Remove the histogram code and its tests. Done when: the pure helpers have `node --test` tests, a controller test covers the payload, and the implementer compares screenshots against the reference page named in §5.5, in light and dark at 1300 and 360 px. Depends on W2.
- [x] **W4: one design system pass (§10).** Audit every page by screenshot in both themes at 1300 and 360 px (Overview all-time, year and month; Runs; a GPS run; an indoor run; Pace Trends; PR Progress), list the inconsistencies in buttons, pills, chips, card title rows, page headers, spacing, empty states, focus rings and hints, and fix them through the shared helpers. Done when: no control or card classes are written inline in views (a grep check), `AGENTS.md` "Views and CSS" states the final rules, and the report lists what changed. Depends on W1 to W3, and runs alone.
- [x] **W5: Phase 2 close-out.** In `AGENTS.md`, "the Phase 3 Pro Map" becomes "the Phase 4 Pro Map", and the new helpers and components are named. Tick this checklist. Rebuild the container and check `/up`, `/overview`, a run page, `/pace_trend` and `/pr_progress` on :9295.

### Phase 3: Wellness and gear

- [x] **W6: Garmin wellness probe (spike, §7.1).** A read-only task, `bin/rails garmin:probe`, that tries each candidate endpoint for yesterday, a date a year ago and the first run's date, at ≤ 1 request/s (about 60 requests). It prints HTTP status, content type, top-level JSON keys with types and array lengths, and the earliest date with data per metric; never values. It writes nothing to the database, and its output goes to `OUTPUT=` (default under the system tmpdir) at mode 600. The Status column in §7.1 is filled in with the real paths, and a short summary is written for the owner. Ask the owner only if resting HR, HRV or sleep is missing (R10). Parallel with W11.
- [x] **W7: wellness data and sync (§5.6, §7.2, §8).** `wellness_days` and the `profiles` columns, `Garmin::Client` methods for the verified endpoints, `Wellness::Sync` and `Wellness::SyncJob` (hourly), `bin/rails wellness:backfill`, `profiles.hr_zones` and the `HrZones` PORO with the default-band fallback. Done when: WebMock tests cover idempotency, the 3-day refresh and missing metrics, and a 30-day dry run on the dev database reports counts only. Depends on W6.
- [x] **W8: HR zones, effort and recovery on the run page (§5.6).** The zones and effort section from the stored summaries, the zone bands on the HR profile, and "Going in". Done when: controller tests cover each section being present or absent per data, a node test covers the zone bar maths, and the browser check covers a run with full data, one without HR and a pre-Garmin run. Depends on W7.
- [x] **W9: Wellness page (§5.6).** The nav item, the shared window and brush, the day cursor, and the charts the probe allows, with empty states. Done when the performance targets in §12 are met. Depends on W7. Parallel with W10.
- [x] **W10: Pace Trends overlay (§5.3, §5.6).** The overlay button group and secondary axis. Depends on W7. Parallel with W9.
- [x] **W11: Strava gear sync (§7.6, §8).** The `profile:read_all` scope, `profiles.strava_scope` and the Reconnect prompt, `gears` and `activities.strava_gear_id`, the Strava client's gear calls, `gear_id` read in the link scans, the weekly gear refresh, the full pass on connect and the hourly recent pass. Done when: WebMock tests cover a missing scope, a gear without a row yet, null gear, an absent `retired` and 401 handling. Owner action after the deploy: click Reconnect Strava. Then check on the live connection, printing counts only. Parallel with W6.
- [x] **W12: Gear page and gear on runs (§5.7).** The table, the "No gear set" row, the two charts, the Refresh button, the runs list column and `gear` filter with the Suggested column, and the header tag. Done when: per-gear distance matches Strava's gear distance within 1% where a gear was only used for runs, every linked run without gear is listed, and tests and the browser check pass. Depends on W11.
- [x] **W13: Phase 3 close-out.** Check the new pages against the design system (§10), update this document and `AGENTS.md`, tick this checklist, rebuild and deploy the container.

### Phase 4: Pro analytics

- [x] **W14: Pro Map (§5.8).** Route colouring from the pace zones and HR zones, distribution bars with the click cycle, fastest segments (computed by `Track::Efforts`, no table), splits, and the change-in-pace graph. Depends on W1 and W8. Parallel with W15 and W16.
- [x] **W15: Training Bands (§5.9).** `activities.bands`, computed in `process_original` and backfilled from the stored tracks with `activities:bands`, and the page. Depends on W8. Parallel with W14 and W16.
- [ ] **W16: Progress Towards Goal (§5.10).** `goals` with CRUD, the chart, and the Overview widgets. Parallel with W14 and W15.
- [ ] **W17: final close-out.** Update this document and `AGENTS.md`, rebuild and deploy the container, and re-check the golden values.

**Owner actions along the way:** click Reconnect Strava after the W11 deploy.
