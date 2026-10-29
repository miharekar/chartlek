require "test_helper"

class PaceTrendsControllerTest < ActionDispatch::IntegrationTest
  test "renders an empty state without runs" do
    get pace_trend_path

    assert_response :success
    assert_select "[data-controller='pace-trends']", false
    assert_select "p", /No runs to show/
    assert_select "nav[aria-label=Performance] a[aria-current=page]", count: 1, text: "Pace Trends"
  end

  test "shows the Performance tabs with Pace Trends current" do
    create(:activity)

    get pace_trend_path

    assert_select "h1", /Performance/
    assert_select "nav[aria-label=Performance] a[href='#{pace_trend_path}'][aria-current=page]", text: "Pace Trends"
    assert_select "nav[aria-label=Performance] a[href='#{pr_progress_path}']:not([aria-current])", text: "PR Progress"
  end

  test "renders the chart with runs" do
    create(:activity)

    get pace_trend_path

    assert_response :success
    assert_select "[data-controller='pace-trends'][data-pace-trends-payload-value]"
    assert_select "[role=group][aria-label='Finish distance'] button[data-action='pace-trends#changeDistance']", count: 4
    assert_select "button[data-distance=Marathon][aria-pressed=true]", "Marathon"
    assert_select "button[data-distance='5K'][aria-pressed=false]"
    assert_select "button[data-controller=info]", minimum: 2
  end

  test "renders the window presets" do
    create(:activity)

    get pace_trend_path

    assert_select "[role=group][aria-label=Window] button[data-action='pace-trends#preset'][aria-pressed]", count: 5
    assert_select "button[data-preset='3']", "3 mo"
    assert_select "button[data-preset='24']", "2 yr"
    assert_select "button[data-preset=all]", "All time"
  end

  test "presets are not rendered without runs" do
    get pace_trend_path

    assert_select "button[data-preset]", false
  end

  test "an old metric parameter is ignored" do
    create(:activity)

    get pace_trend_path(metric: "vdot")

    assert_response :success
    assert_select "[data-controller='pace-trends'][data-pace-trends-payload-value]"
    assert_select "a[href*=metric]", false
  end

  test "payload escapes run names" do
    create(:activity, name: "<script>alert(1)</script>")

    get pace_trend_path

    assert_no_match "<script>alert(1)</script>", response.body
  end

  test "each filter renders" do
    create(:activity, race: true)
    create(:activity, indoor: true)

    [{no_pauses: "1"}, {races: "1"}, {races: "1", no_pauses: "1", from: "2024-01-01", to: "2024-03-01", distance: "5K"}].each do |query|
      get pace_trend_path(query)

      assert_response :success, query.inspect
      assert_select "[data-controller='pace-trends']"
    end
  end

  test "the old no_indoor param is ignored" do
    create(:activity, indoor: true)

    get pace_trend_path(no_indoor: "1")

    assert_response :success
    assert_select "[data-controller='pace-trends']"
    assert_select "button[aria-pressed], a[aria-pressed]", text: /treadmill/i, count: 0
  end

  test "filters that exclude every run show the empty state" do
    create(:activity)

    get pace_trend_path(races: "1")

    assert_response :success
    assert_select "[data-controller='pace-trends']", false
    assert_select "p", /No runs to show with these filters/
    assert_select "a[aria-pressed=true]", "Races only"
  end

  test "chip links toggle filters and keep the window" do
    create(:activity)

    get pace_trend_path(races: "1", from: "2024-01-01", to: "2024-02-01")

    assert_select "a[href=?]", pace_trend_path(from: "2024-01-01", to: "2024-02-01"), "Races only"
    assert_select "a[href=?]", pace_trend_path(races: "1", from: "2024-01-01", to: "2024-02-01", no_pauses: "1"), "Exclude pauses"
  end

  test "ignores unknown query params in chip links" do
    get pace_trend_path(evil: "x")

    assert_select "a[href*=evil]", false
  end

  test "no overlay buttons without wellness data" do
    create(:activity)

    get pace_trend_path(overlay: "rhr")

    assert_select "[role=group][aria-label=Overlay]", false
    assert_equal({}, payload.slice("overlay", "overlays").compact)
  end

  test "overlay buttons offer only the series with data and default to none" do
    create(:activity)
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52)

    get pace_trend_path

    assert_select "[role=group][aria-label=Overlay] button[data-action='pace-trends#changeOverlay']", count: 2
    assert_select "button[data-overlay=none][aria-pressed=true]", "None"
    assert_select "button[data-overlay=rhr][aria-pressed=false]", "Resting HR"
    assert_select "button[data-overlay=hrv]", false
    assert_nil payload["overlay"]
    assert_equal [52], payload["overlays"]["rhr"]
  end

  test "the overlay param is kept in the payload and chip links" do
    create(:activity)
    WellnessDay.create!(date: Date.new(2024, 3, 5), hrv_last_night: 60)

    get pace_trend_path(overlay: "hrv", from: "2024-01-01")

    assert_select "button[data-overlay=hrv][aria-pressed=true]", "HRV"
    assert_equal "hrv", payload["overlay"]
    assert_select "a[href=?]", pace_trend_path(overlay: "hrv", from: "2024-01-01", races: "1"), "Races only"
  end

  test "a sleep overlay is offered with sleep data and carries the nightly seconds" do
    create(:activity)
    WellnessDay.create!(date: Date.new(2024, 3, 5), sleep_s: 27_000)

    get pace_trend_path(overlay: "sleep")

    assert_select "button[data-overlay=sleep][aria-pressed=true]", "Sleep"
    assert_equal "sleep", payload["overlay"]
    assert_equal [27_000], payload["overlays"]["sleep"]
  end

  test "an overlay without data or an unknown one is ignored" do
    create(:activity)
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52)

    get pace_trend_path(overlay: "hrv")
    assert_nil payload["overlay"]

    get pace_trend_path(overlay: "evil")
    assert_nil payload["overlay"]
  end

  private
  def payload
    JSON.parse(css_select("[data-controller='pace-trends']").first["data-pace-trends-payload-value"])
  end
end
