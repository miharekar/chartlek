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
    assert_select "section h2", text: "Notables"
    assert_select "h2", text: "Fastest runs at this distance"
  end

  test "show renders weather, calories, track extents and navigation" do
    earlier = run_at(Time.utc(2023, 5, 5, 7))
    run = run_at(Time.utc(2023, 5, 6, 7), name: "Full", calories: 650, avg_hr: 150, max_hr: 190, avg_cadence: 170, max_cadence: 185, location_name: "Ljubljana", elapsed_s: 3100, moving_s: 3000, pace_variability: 6.5, elevation_gain_m: 40, elevation_loss_m: 38, weather: {"temperature" => 14.2, "humidity" => 60, "wind" => 8, "precipitation" => 0})
    same_day = run_at(Time.utc(2023, 5, 6, 18))
    Track.create!(activity: run, data: {"t" => [0, 1, 2], "d" => [0, 5, 10], "hr" => [120, 150, 180], "cad" => [160, 170, 180]})

    get run_path(run)

    assert_response :success
    assert_select "p", text: /14°C · 60% humidity · wind 8 km\/h/
    assert_select "p", text: /Ljubljana/
    assert_select "p", text: /120–180/
    assert_select "p", text: /160–180/
    assert_select "p", text: /≈/
    assert_select "h2", text: /Pace variability/
    assert_select "p", text: /6\.5/
    assert_select "[data-controller=recording-bars]", false
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
      assert_select "a.bg-lime-700", text: "2023"
      assert_select "a.bg-lime-700", text: "May"
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

  test "the finish times sit inside the VDOT tile as a grid of four" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 10_000, timer_s: 3000)

    get run_path(run)

    assert_select "dl[aria-label^='Estimated finish times'] dt", text: "5K"
    assert_select "dl[aria-label^='Estimated finish times'] dt", text: "Marathon"
    vdot_tile = css_select("section").find { it.at_css("h2")&.text&.strip&.start_with?("VDOT") }
    assert vdot_tile.at_css("dl")
    assert_equal 4, vdot_tile.css("dt").size
    assert_equal 1, css_select("dl[aria-label^='Estimated finish times']").size
  end

  test "without a VDOT the tile shows a dash and no grid" do
    run = run_at(Time.utc(2023, 5, 6, 7), distance_m: 300, timer_s: 100)

    get run_path(run)

    assert_response :success
    vdot_tile = css_select("section").find { it.at_css("h2")&.text&.strip&.start_with?("VDOT") }
    assert_equal "–", vdot_tile.at_css("p").text.strip
    assert_nil vdot_tile.at_css("dl")
    assert_select "dl[aria-label^='Estimated finish times']", false
  end

  test "show draws the pace variability wheel from the 100 m bars" do
    run = run_at(Time.utc(2023, 5, 6, 7), pace_variability: 6.5)
    Track.create!(activity: run, data: {"t" => [0, 30, 50, 90], "d" => [0, 100, 200, 300]}, chart_metrics: {"elevation" => nil})

    get run_path(run)

    assert_select "[data-controller=pace-variability][data-pace-variability-percent-value='6.5']"
    assert_select "[data-controller=pace-variability][data-pace-variability-bars-value=?]", [{from: 0.0, to: 0.1, distance: 100.0, time: 30.0}, {from: 0.1, to: 0.2, distance: 100.0, time: 20.0}, {from: 0.2, to: 0.3, distance: 100.0, time: 40.0}].to_json
    assert_select "[data-pace-variability-target=chart][role=group][aria-label*='100 metres']"
    assert_select "[data-controller=recording-bars]", false
    assert_select "p", text: /Green: faster/, count: 0
    assert_select "section.col-span-2.sm\\:col-span-1 h2", text: /Pace variability/
  end

  test "show has no wheel when the variability is missing" do
    run = run_at(Time.utc(2023, 5, 6, 7), pace_variability: nil)

    get run_path(run)

    assert_select "[data-controller=pace-variability]", false
    assert_select "h2", text: /Pace variability/, count: 0
    assert_select "section.lg\\:col-span-2 h2", text: /longest run/
    assert_select "section.sm\\:col-span-1.lg\\:col-span-2 h2", text: /fastest for a similar distance/
  end

  test "show is a 404 for an unknown run" do
    get "/runs/0"

    assert_response :not_found
  end
end
