require "test_helper"

class PagesTest < ActionDispatch::IntegrationTest
  test "root redirects to overview" do
    get "/"

    assert_redirected_to "/overview"
  end

  test "pages render" do
    %w[/overview /overview/2024 /overview/2024/3 /overview/2024/03 /overview/2024/09 /overview/2024/12 /pace_trend /pr_progress].each do |path|
      get path

      assert_response :success, path
    end
  end

  test "the main nav marks Performance current on both of its tabs" do
    %w[/pace_trend /pr_progress].each do |path|
      get path

      assert_select "nav[aria-label=Main] a[aria-current=page]", count: 1, text: "Performance"
    end
  end

  test "the main nav marks Runs current on a run page" do
    run = create(:activity)

    get run_path(run)

    assert_select "nav[aria-label=Main] a[aria-current=page]", count: 1, text: "Runs"
  end

  test "the main nav holds Performance instead of its two tabs" do
    get "/overview"

    assert_select "nav[aria-label=Main] a", text: "Performance"
    assert_select "nav[aria-label=Main] a", text: "Pace Trends", count: 0
    assert_select "nav[aria-label=Main] a", text: "PR Progress", count: 0
  end

  test "overview constrains year and month" do
    get "/overview/24"
    assert_response :not_found

    %w[/overview/2024/123 /overview/2024/13 /overview/2024/0].each do |path|
      get path

      assert_response :not_found, path
    end
  end
end
