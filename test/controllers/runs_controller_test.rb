require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  def run_at(time, **attrs)
    create(:activity, local_started_at: time, started_at: time, **attrs)
  end

  test "index defaults to the current year" do
    current = run_at(Time.current.utc.beginning_of_day, name: "Now Run")
    run_at(Time.utc(2020, 5, 1), name: "Old Run")

    get "/runs"

    assert_response :success
    assert_select "a[href=?]", run_path(current), text: "Now Run"
    assert_select "a", text: "Old Run", count: 0
  end

  test "index filters by year and month and offers all" do
    run_at(Time.utc(2023, 5, 6, 7), name: "May Run")
    run_at(Time.utc(2023, 6, 6, 7), name: "June Run")
    run_at(Time.utc(2022, 6, 6, 7), name: "Older Run")

    get "/runs", params: {year: 2023, month: 5}

    assert_select "a", text: "May Run"
    assert_select "a", text: "June Run", count: 0
    assert_select "a[href=?]", runs_path(year: "all"), text: "All"

    get "/runs", params: {year: "all"}

    assert_select "tbody tr", 3
  end

  test "index shows race and treadmill tags" do
    run_at(Time.utc(2023, 5, 6, 7), race: true, indoor: true)

    get "/runs", params: {year: 2023}

    assert_select "span", text: "race"
    assert_select "span", text: "treadmill"
  end

  test "index sorts by a whitelisted column and ignores others" do
    run_at(Time.utc(2023, 5, 6, 7), name: "Short", distance_m: 5000, timer_s: 1500)
    run_at(Time.utc(2023, 5, 7, 7), name: "Long", distance_m: 20_000, timer_s: 6000)

    get "/runs", params: {year: 2023, sort: "km", dir: "asc"}

    assert_select "tbody tr:first-child td:nth-child(2)", text: "Short"

    get "/runs", params: {year: 2023, sort: "name; DROP TABLE activities", dir: "desc"}

    assert_response :success
    assert_select "tbody tr:first-child td:nth-child(2)", text: "Long"
  end

  test "index renders an empty state" do
    get "/runs", params: {year: 2019}

    assert_response :success
    assert_select "p", text: /No runs/
    assert_select "table", false
  end

  test "show renders a bare run without track, weather, splits or calories" do
    run = run_at(Time.utc(2023, 5, 6, 7), name: "Bare")

    get run_path(run)

    assert_response :success
    assert_select "h1", text: /Bare/
    assert_select "a[href=?]", "https://connect.garmin.com/app/activity/#{run.external_id}"
    assert_select "ul[aria-label=Notables] li span", minimum: 1
    assert_select "h2", text: "Notables", count: 0
    assert_select "h2", text: "Fastest runs at this distance"
  end

  test "show renders the workout card only for workouts and the list tags them" do
    steps = [{"splitType" => "INTERVAL_WARMUP", "distance" => 2000, "duration" => 600}, {"splitType" => "INTERVAL_ACTIVE", "noOfSplits" => 4, "distance" => 4000, "duration" => 960}, {"splitType" => "INTERVAL_REST", "distance" => 0, "duration" => 90}]
    workout = run_at(Time.utc(2023, 5, 6, 7), summary: {"splitSummaries" => steps})
    plain = run_at(Time.utc(2023, 5, 7, 7), summary: {"splitSummaries" => [{"splitType" => "INTERVAL_ACTIVE", "noOfSplits" => 1}]})

    get run_path(workout)

    assert_select "h2", text: /Workout/
    assert_select "td", text: "Active ×4"
    assert_select "td", text: "4:00 /km"

    get run_path(plain)

    assert_select "h2", text: /Workout/, count: 0

    get "/runs", params: {year: 2023}

    assert_select "span", text: "workout", count: 1
  end

  test "show renders weather, calories, track extents and navigation" do
    earlier = run_at(Time.utc(2023, 5, 5, 7))
    run = run_at(Time.utc(2023, 5, 6, 7), name: "Full", calories: 650, avg_hr: 150, max_hr: 190, avg_cadence: 170, max_cadence: 185, location_name: "Ljubljana", elapsed_s: 3100, moving_s: 3000, pace_variability: 6.5, elevation_gain_m: 40, elevation_loss_m: 38, weather: {"temperature" => 14.2, "humidity" => 60, "wind" => 8, "precipitation" => 0})
    same_day = run_at(Time.utc(2023, 5, 6, 18))
    Track.create!(activity: run, data: {"t" => [0, 1, 2], "d" => [0, 5, 10], "hr" => [120, 150, 180], "cad" => [160, 170, 180]})

    get run_path(run)

    assert_response :success
    assert_select "span", text: "14°C"
    assert_select "span", text: /60%/
    assert_select "span.sr-only", text: "humidity"
    assert_select "span", text: /8 km\/h/
    assert_select "span.sr-only", text: "wind"
    assert_select "p", text: /Ljubljana/
    assert_select "p", text: /120–180/
    assert_select "p", text: /160–180/
    assert_select "p", text: /≈/
    assert_select "h2", text: /Pace variability/
    assert_select "p", text: /6\.5/
    assert_select "a[href=?]", run_path(earlier)
    assert_select "a[href=?]", run_path(same_day), text: "Next →"
    assert_select "nav[aria-label='Runs that day'] a[href=?]", run_path(same_day)
  end

  test "show renders the date navigator for the run's year, month and day" do
    run_at(Time.utc(2022, 8, 1, 7))
    march = run_at(Time.utc(2023, 3, 9, 7))
    race = run_at(Time.utc(2023, 5, 7, 7), race: true, distance_m: 10_000, timer_s: 3000)
    run = run_at(Time.utc(2023, 5, 6, 7))
    later = run_at(Time.utc(2023, 5, 6, 18))

    get run_path(run)

    assert_response :success
    assert_select "nav[aria-label='Run calendar']" do
      assert_select "a", text: /^2023$|^2022$/, count: 2
      assert_select "a[href=?]", run_path(race), text: "2023"
      assert_select "a[aria-current=page]", text: "2023"
      assert_select "a[aria-current=page]", text: "May"
      assert_select "a[href=?]", run_path(march), text: "Mar"
      assert_select "span", text: "Jan"
      assert_select "a", text: "Feb", count: 0
      assert_select "a[aria-current=page]", text: "6"
      assert_select "a[href=?]", run_path(run), text: "6"
      assert_select "a[href=?]", run_path(later), text: "6", count: 0
      assert_select "a[href=?][aria-label*='race'][data-day-tip-text-value*='10.0 km']", run_path(race), text: "7"
      assert_select "span", text: "8"
      assert_select "div:last-child > *", count: 31
    end
  end

  test "date navigator selects the day when viewing a later run that day" do
    first = run_at(Time.utc(2023, 5, 6, 7))
    later = run_at(Time.utc(2023, 5, 6, 18))

    get run_path(later)

    assert_select "nav[aria-label='Run calendar'] a[aria-current=page]", text: "6", count: 1
    assert_select "nav[aria-label='Run calendar'] a[aria-current=page][href=?]", run_path(first)
  end

  test "date navigator handles a leap month and never renders run names" do
    run = run_at(Time.utc(2024, 2, 29, 7), name: "<b>x</b>")

    get run_path(run)

    assert_select "nav[aria-label='Run calendar'] b", false
    assert_select "nav[aria-label='Run calendar'] a[aria-current=page]", text: "29"
  end

  test "show offers Open in Garmin and, once linked, Open in Strava" do
    run = run_at(Time.utc(2023, 5, 6, 7))

    get run_path(run)

    assert_select "a[href=?][target=_blank]", "https://connect.garmin.com/app/activity/#{run.external_id}", text: "Open in Garmin"
    assert_select "a", text: "Open in Strava", count: 0

    run.update!(strava_id: 777)
    get run_path(run)

    assert_select "a[href=?][target=_blank]", "https://connect.garmin.com/app/activity/#{run.external_id}", text: "Open in Garmin"
    assert_select "a[href=?][target=_blank][rel=noopener]", "https://www.strava.com/activities/777", text: "Open in Strava"
  end

  test "show offers only Strava for a strava sourced run" do
    run = run_at(Time.utc(2016, 5, 6, 7), source: "strava", external_id: "4242")

    get run_path(run)

    assert_select "a", text: "Open in Garmin", count: 0
    assert_select "a[href=?]", "https://www.strava.com/activities/4242", text: "Open in Strava"
  end

  test "show has no external link for a smashrun run" do
    run = run_at(Time.utc(2015, 3, 3, 15), source: "smashrun")

    get run_path(run)

    assert_response :success
    assert_select "a[target=_blank]", false
  end

  test "show highlights the run among the fastest and finishes with vdot" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 5000, timer_s: 1300)

    get run_path(run)

    assert_select "tr.font-medium", 4
    assert_select "h3", text: "All time"
    assert_select "h2", text: /Estimated finish times/, count: 0
    assert_select "h2", text: /1st longest run/
  end

  test "the performance card shows the vdot, the zone strip and one finish at a time" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 10_000, timer_s: 3000)

    get run_path(run)

    card = css_select("section").find { it.at_css("h2")&.text&.strip&.start_with?("Performance index") }
    assert_equal run.vdot.round(1).to_s, card.at_css("p").text.strip
    assert_equal run.performance_zone_range.size, card.css("span[title][style*='--pace-zone-']").size
    assert_operator card.css("span[title][style*='--pace-zone-']").size, :<, PaceZones::COUNT
    assert_includes card.text, "5K pace #{ApplicationController.helpers.overview_pace(Vdot.time_for(5000, run.vdot) / 5)} /km"
    assert_equal "5K", card.at_css("[data-estimated-finish-target=label]").text
    assert_equal ApplicationController.helpers.overview_duration(Vdot.time_for(5000, run.vdot)), card.at_css("[data-estimated-finish-target=time]").text
    assert_equal 1, card.css("[aria-live=polite]").size
    assert_equal 1, card.css("button[data-action='estimated-finish#next']").size
    finishes = JSON.parse(card.at_css("[data-controller=estimated-finish]")["data-estimated-finish-finishes-value"])
    assert_equal %w[5K 10K Half Marathon], finishes.pluck("label")
    assert_select "dl[aria-label^='Estimated finish times']", false
  end

  test "the performance dot is centred on its zone in the strip" do
    best = run_at(Time.utc(2022, 1, 1, 7), distance_m: 5000, timer_s: 1200)
    slow = run_at(Time.utc(2023, 5, 6, 7), distance_m: 5000, timer_s: 4000)

    range = [slow.performance_zone - 1, 0].max..(best.performance_zone + 1)

    {best => best.performance_zone, slow => slow.performance_zone}.each do |run, zone|
      left = (zone - range.begin + 0.5) * 100.0 / range.size
      get run_path(run)

      dot = css_select("[role=img][aria-label^='Performance zone'] span.rounded-full").sole
      assert_in_delta left, dot["style"][/left: ([\d.]+)%/, 1].to_f, 1e-6
      assert_includes dot["class"], "-translate-y-1/2"
    end
  end

  test "without a VDOT the performance card shows dashes and no strip" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 300, timer_s: 100)

    get run_path(run)

    assert_response :success
    card = css_select("section").find { it.at_css("h2")&.text&.strip&.start_with?("Performance index") }
    assert_equal "–", card.at_css("p").text.strip
    assert_equal 2, card.css("p").size
    assert_nil card.at_css("span[title]")
    assert_nil card.at_css("[data-controller=estimated-finish]")
    assert_nil card.at_css("button[data-action^='estimated-finish']")
  end

  test "show draws the pace variability wheel from the 100 m bars" do
    run = run_at(Time.utc(2023, 5, 6, 7), pace_variability: 6.5)
    Track.create!(activity: run, data: {"t" => [0, 30, 50, 90], "d" => [0, 100, 200, 300]}, chart_metrics: {"elevation" => nil})

    get run_path(run)

    assert_select "[data-controller=pace-variability][data-pace-variability-percent-value='6.5']"
    assert_select "[data-controller=pace-variability][data-pace-variability-bars-value=?]", [{from: 0.0, to: 0.1, distance: 100.0, time: 30.0}, {from: 0.1, to: 0.2, distance: 100.0, time: 20.0}, {from: 0.2, to: 0.3, distance: 100.0, time: 40.0}].to_json
    assert_select "[data-pace-variability-target=chart][role=group][aria-label*='100 metres']"
    assert_select "p", text: /Green: faster/, count: 0
    assert_select "section.col-span-2.lg\\:col-span-1 h2", text: /Pace variability/
  end

  test "show has no wheel when the variability is missing" do
    run = run_at(Time.utc(2023, 5, 6, 7), pace_variability: nil)

    get run_path(run)

    assert_select "[data-controller=pace-variability]", false
    assert_select "h2", text: /Pace variability/, count: 0
    assert_select "section.col-span-2:not(.lg\\:col-span-1) h2", text: /longest run/
    assert_select "section.col-span-2:not(.lg\\:col-span-4) h2", text: /fastest for a similar distance/
  end

  test "show is a 404 for an unknown run" do
    get "/runs/0"

    assert_response :not_found
  end

  test "the elevation profile card shows the chart, the run's totals and its hill difficulty" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 10_000, timer_s: 3000, pace_variability: 6.5, elevation_gain_m: 150.4, elevation_loss_m: 148.2)
    Track.create!(activity: run, data: {"t" => [0, 30, 60], "d" => [0, 100, 200], "alt" => [100.0, nil, 130.0]})

    get run_path(run)

    assert_select "section:has(h2)" do
      assert_select "h2", text: /Elevation profile/
    end
    assert_select "[data-controller=elevation-profile][data-elevation-profile-distances-value=?]", "[0,100,200]"
    assert_select "[data-controller=elevation-profile][data-elevation-profile-altitudes-value=?]", "[100.0,null,130.0]"
    assert_select "dt", text: "Hill difficulty"
    assert_select "dd", text: "3"
    assert_select "dd", text: "+150m"
    assert_select "dd", text: "−148m"
    assert_select "section.col-span-2.lg\\:col-span-4 h2", text: /fastest for a similar distance/
  end

  test "without altitude there is no elevation profile card and the fastest tile keeps its width" do
    run = run_at(Time.utc(2023, 5, 6, 7), pace_variability: 6.5)
    Track.create!(activity: run, data: {"t" => [0, 30, 60], "d" => [0, 100, 200]})

    get run_path(run)

    assert_select "[data-controller=elevation-profile]", false
    assert_select "h2", text: /Elevation profile/, count: 0
    assert_select "section.lg\\:col-span-4", false
  end

  test "a run with elevation gain but no altitude track shows its totals without the chart" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 10_000, timer_s: 3000, elevation_gain_m: 150.4, elevation_loss_m: 148.2)

    get run_path(run)

    assert_select "h2", text: "Elevation"
    assert_select "h2", text: /Elevation profile/, count: 0
    assert_select "[data-controller=elevation-profile]", false
    assert_select "dd", text: "+150m"
    assert_select "dd", text: "−148m"
    assert_select "dt", text: "Hill difficulty"
    assert_select "section.col-span-2.lg\\:col-span-4 h2", text: /fastest for a similar distance/
  end

  test "the analyze chart gets this run's figures and a legend" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 8000, timer_s: 2400, race: true)
    run_at(Time.utc(2023, 5, 1, 7))

    get run_path(run)

    assert_select "[data-controller=analyze-run][data-analyze-run-current-value*='\"race\":true']"
    assert_select "[data-controller=analyze-run][data-analyze-run-current-value*='\"km\":8.0']"
    assert_select "p", text: /This run.*Average.*Previous runs/m
    assert_select "h2", text: /Runs in the prior 90 days/
    assert_select "[role=group][aria-label=Metric] button[data-action='analyze-run#metric']", count: 4
    assert_select "button[value=km][aria-pressed=true]", "Distance"
    assert_select "select", false
    assert_select "[data-analyze-run-target=strip]"
    assert_select "[data-analyze-run-target=timeline]"
  end

  test "the analyze card says so when there are no runs in the window" do
    run = run_at(Time.utc(2023, 5, 6, 7))

    get run_path(run)

    assert_select "p", text: "No runs in the 90 days before this one."
    assert_select "[data-controller=analyze-run]", false
  end

  def gear_scanned
    Profile.instance.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 6.hours.from_now.to_i)
    Profile.instance.update!(strava_scope: "read,activity:read_all,profile:read_all", strava_gear_synced_at: Time.current)
  end

  def linked_run(at, gear_id: nil, **attrs)
    run_at(at, strava_id: rand(1_000_000) + 1, strava_gear_id: gear_id, **attrs)
  end

  test "gear none lists only linked runs without gear, with suggestions and Open in Strava" do
    gear_scanned
    Gear.create!(strava_id: "g1", name: "Synthetic Shoe")
    fixable = linked_run(Time.utc(2023, 5, 6, 7), name: "Fix Me")
    linked_run(Time.utc(2023, 5, 5, 7), gear_id: "g1", name: "Has Gear")
    run_at(Time.utc(2023, 5, 7, 7), name: "Unlinked")

    get "/runs", params: {year: 2023, gear: "none"}

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "a", text: "Fix Me"
    assert_select "th", text: "Suggested"
    assert_select "tbody td a[href=?]", runs_path(gear: "g1", year: "all"), text: "Synthetic Shoe"
    assert_select "tbody td a[href=?][target=_blank]", fixable.strava_url, text: "Open in Strava"
    assert_select "tbody td a", text: "No gear"
  end

  test "gear filter keeps one gear and the period links keep the filter" do
    Gear.create!(strava_id: "g1", name: "Synthetic Shoe")
    linked_run(Time.utc(2023, 5, 6, 7), gear_id: "g1", name: "On It")
    linked_run(Time.utc(2023, 5, 7, 7), name: "Off It")

    get "/runs", params: {year: 2023, gear: "g1"}

    assert_select "tbody tr", 1
    assert_select "a", text: "On It"
    assert_select "th", text: "Suggested", count: 0
    assert_select "span", text: "Synthetic Shoe"
    assert_select "a[href=?]", runs_path(year: "all", gear: "g1"), text: "All"
  end

  test "the gear column shows gear, No gear, or nothing for an unlinked run" do
    gear_scanned
    Gear.create!(strava_id: "g1", name: "Synthetic Shoe")
    linked_run(Time.utc(2023, 5, 6, 7), gear_id: "g1")
    linked_run(Time.utc(2023, 5, 7, 7))
    run_at(Time.utc(2023, 5, 8, 7))

    get "/runs", params: {year: 2023}

    assert_select "tbody tr:nth-child(3) td:nth-last-child(2) a", text: "Synthetic Shoe"
    assert_select "tbody tr:nth-child(2) td:nth-last-child(2) a", text: "No gear"
    assert_select "tbody tr:nth-child(1) td:nth-last-child(2) a", false
  end

  test "the run header has a gear line under the date and above the weather, an amber No gear, or nothing" do
    gear_scanned
    Gear.create!(strava_id: "g1", name: "Synthetic Shoe")
    geared = linked_run(Time.utc(2023, 5, 6, 7), gear_id: "g1", weather: {"temperature" => 14.2})
    bare = linked_run(Time.utc(2023, 5, 7, 7))
    unlinked = run_at(Time.utc(2023, 5, 8, 7))

    get run_path(geared)
    assert_select "header p:nth-of-type(2) a[href=?]", runs_path(gear: "g1", year: "all"), text: "Synthetic Shoe"
    assert_select "header p:nth-of-type(2) svg[aria-hidden=true]"
    assert_select "header p:nth-of-type(3) span", text: "14°C"
    assert_select "header nav a", text: "Synthetic Shoe", count: 0
    assert_select "header p.text-zinc-600", 3

    get run_path(bare)
    assert_select "header p:nth-of-type(2) a[href=?].text-amber-700", runs_path(gear: "none", year: "all"), text: "No gear"

    get run_path(unlinked)
    assert_select "header a[href*=gear]", false
  end

  test "no gear tag or gear line and no amber No gear before the first full gear scan" do
    run = linked_run(Time.utc(2023, 5, 6, 7), gear_id: "g1")
    bare = linked_run(Time.utc(2023, 5, 7, 7))

    get "/runs", params: {year: 2023}

    assert_select "tbody a[href*=gear]", false
    assert_select "tbody td a", text: "No gear", count: 0

    get run_path(run)
    assert_select "header a[href*=gear]", false

    get run_path(bare)
    assert_select "header a[href*=gear]", false
    assert_select "header svg[aria-hidden=true]", false
  end

  test "the gear none hint says older runs need Refresh from Strava" do
    get "/runs", params: {gear: "none"}

    assert_select "p", text: /a recent run leaves this list after the next hourly scan, an older one after Refresh from Strava/
  end

  test "Show all gear from an all-time gear list keeps all time" do
    linked_run(Time.utc(2019, 5, 6, 7), gear_id: "g1")

    get "/runs", params: {gear: "g1"}

    assert_select "a[href=?]", runs_path(year: "all"), text: "Show all gear"
  end

  test "a non-scalar gear param is ignored instead of failing" do
    run_at(Time.utc(2023, 5, 6, 7), name: "Plain")

    get "/runs?year=2023&gear[a]=b"

    assert_response :success
    assert_select "a", text: "Plain"
  end

  test "gear none with nothing to fix says so" do
    linked_run(Time.utc(2023, 5, 6, 7), gear_id: "g1")

    get "/runs", params: {gear: "none"}

    assert_response :success
    assert_select "p", text: "Every run linked to Strava has gear set."
    assert_select "table", false
  end

  test "gear none defaults to all time so older unset runs are listed" do
    linked_run(Time.utc(2019, 5, 6, 7), name: "Old Unset")

    get "/runs", params: {gear: "none"}

    assert_select "a", text: "Old Unset"
    assert_select "p", text: /Every run linked to Strava has gear set/, count: 0
  end

  test "a gear filter with no runs in the chosen year keeps the filter on Show all time" do
    linked_run(Time.utc(2019, 5, 6, 7), gear_id: "g1")

    get "/runs", params: {gear: "g1", year: 2023}

    assert_select "p", text: /No runs in 2023/
    assert_select "a[href=?]", runs_path(year: "all", gear: "g1"), text: "Show all time"
    assert_select "p", text: /Every run linked to Strava/, count: 0
  end

  test "gear none for a past year with nothing unset shows the period empty state, not the all-clear" do
    linked_run(Time.utc(2019, 5, 6, 7))

    get "/runs", params: {gear: "none", year: 2023}

    assert_select "p", text: /No runs in 2023/
    assert_select "p", text: /Every run linked to Strava/, count: 0
  end
end
