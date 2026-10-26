require "test_helper"

class PaceTrendsControllerTest < ActionDispatch::IntegrationTest
  test "renders an empty state without runs" do
    get pace_trend_path

    assert_response :success
    assert_select "[data-controller='pace-trends']", false
    assert_select "p", /No runs to show/
  end

  test "renders the chart with runs" do
    create(:activity)

    get pace_trend_path

    assert_response :success
    assert_select "[data-controller='pace-trends'][data-pace-trends-payload-value]"
    assert_select "select option[selected]", "Marathon"
    assert_select "button[data-controller=info]", minimum: 2
  end

  test "payload escapes run names" do
    create(:activity, name: "<script>alert(1)</script>")

    get pace_trend_path

    assert_no_match "<script>alert(1)</script>", response.body
  end

  test "each filter and metric renders" do
    create(:activity, race: true)
    create(:activity, indoor: true)

    [{metric: "vdot"}, {no_pauses: "1"}, {no_indoor: "1"}, {races: "1"}, {metric: "vdot", races: "1", no_indoor: "1", no_pauses: "1", from: "2024-01-01", to: "2024-03-01", distance: "5K"}].each do |query|
      get pace_trend_path(query)

      assert_response :success, query.inspect
      assert_select "[data-controller='pace-trends']"
    end
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
    assert_select "a[href=?]", pace_trend_path(races: "1", from: "2024-01-01", to: "2024-02-01", metric: "vdot"), "VDOT"
  end

  test "ignores unknown query params in chip links" do
    get pace_trend_path(evil: "x")

    assert_select "a[href*=evil]", false
  end
end
