require "test_helper"

class PrProgressesControllerTest < ActionDispatch::IntegrationTest
  test "shows an empty state without runs" do
    get pr_progress_path

    assert_response :success
    assert_select "[data-controller=pr-progress]", false
    assert_select "p", text: "No runs to show yet."
  end

  test "renders the chart controller with the serialized runs" do
    create(:activity, distance_m: 10_000, timer_s: 2700, local_started_at: Time.utc(2024, 3, 5, 7, 30))

    get pr_progress_path

    assert_response :success
    assert_select "[data-controller=pr-progress][data-pr-progress-mode-value=progress][data-pr-progress-days-value=90]"
    data = JSON.parse(css_select("[data-controller=pr-progress]").first["data-pr-progress-data-value"])
    assert_equal 1, data["runs"].size
    assert_equal 1, data["frontier"].size
    assert_select "span[title]", text: "ⓘ", minimum: 2
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
