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
