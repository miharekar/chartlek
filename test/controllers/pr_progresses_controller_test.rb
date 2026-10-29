require "test_helper"

class PrProgressesControllerTest < ActionDispatch::IntegrationTest
  test "shows an empty state without runs" do
    get pr_progress_path

    assert_response :success
    assert_select "[data-controller=pr-progress]", false
    assert_select "p", text: "No runs to show yet."
    assert_select "nav[aria-label=Performance] a[aria-current=page]", count: 1, text: "PR Progress"
  end

  test "shows the Performance tabs with PR Progress current" do
    create(:activity)

    get pr_progress_path

    assert_select "h1", /Performance/
    assert_select "nav[aria-label=Performance] a[href='#{pr_progress_path}'][aria-current=page]", text: "PR Progress"
    assert_select "nav[aria-label=Performance] a[href='#{pace_trend_path}']:not([aria-current])", text: "Pace Trends"
  end

  test "renders the chart controller with the serialized runs" do
    create(:activity, distance_m: 10_000, timer_s: 2700, local_started_at: Time.utc(2024, 3, 5, 7, 30))

    get pr_progress_path

    assert_response :success
    assert_select "[data-controller=pr-progress][data-pr-progress-mode-value=progress][data-pr-progress-days-value=90]"
    data = JSON.parse(css_select("[data-controller=pr-progress]").first["data-pr-progress-data-value"])
    assert_equal 1, data["runs"].size
    assert_equal 1, data["frontier"].size
    assert_select "button[data-controller=info]", minimum: 2
    assert_select "[data-pr-progress-target=table]"
  end

  test "the best in window card is titled and the window block replaces the window card" do
    create(:activity)

    get pr_progress_path

    assert_select "h2", /Best in window/
    assert_select "h2", {text: /\AWindow/, count: 0}
    assert_select "section [data-pr-progress-target=table]"
  end

  test "from and to set the window the chart starts on, and garbage falls back to the last year" do
    create(:activity, local_started_at: Time.utc(2024, 3, 5, 7))

    get pr_progress_path(from: "2024-02-01", to: "2024-03-31", mode: "beat", days: 60)

    data = JSON.parse(css_select("[data-controller=pr-progress]").first["data-pr-progress-data-value"])
    assert_equal [Time.utc(2024, 2, 1), Time.utc(2024, 4, 1)].map { it.to_i * 1000 }, data["window"]
    assert_select "[data-pr-progress-mode-value=beat][data-pr-progress-days-value=60]"

    get pr_progress_path(from: "garbage", to: "2024-13-45", mode: "nope", days: "x")

    data = JSON.parse(css_select("[data-controller=pr-progress]").first["data-pr-progress-data-value"])
    today = Activity.today
    assert_equal [(today << 12).to_time(:utc).to_i * 1000, (today + 1).to_time(:utc).to_i * 1000], data["window"]
    assert_select "[data-pr-progress-mode-value=progress][data-pr-progress-days-value=90]"
  end

  test "mode and days come from params" do
    create(:activity)

    get pr_progress_path(mode: "magic", days: 60)

    assert_select "[data-pr-progress-mode-value=magic][data-pr-progress-days-value=60]"
  end

  test "unknown mode and days fall back to defaults" do
    create(:activity)

    get pr_progress_path(mode: "nope", days: 7)

    assert_select "[data-pr-progress-mode-value=progress][data-pr-progress-days-value=90]"
  end
end
