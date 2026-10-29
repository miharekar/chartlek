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

  test "the main nav marks Overview current on the goal pages and has no Goals link" do
    goal = Goal.create!(period: "month", starts_on: Date.new(2024, 3, 1), distance_km: 100)

    [goal_path(goal), new_goal_path, goals_path].each do |path|
      get path

      assert_select "nav[aria-label=Main] a[aria-current=page]", count: 1, text: "Overview"
    end
    assert_select "nav[aria-label=Main] a", text: "Goals", count: 0
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

  test "the nav links to GitHub in a new tab" do
    get "/overview"

    assert_select "nav a[href='https://github.com/miharekar/chartlek'][aria-label='Chartlek on GitHub'][title='Chartlek on GitHub'][target=_blank][rel=noopener]"
  end

  test "Sync now sits outside the live sync status" do
    get "/overview"

    assert_select "#sync_status form", false
    assert_select "nav form[action='#{sync_path}']"
  end

  test "the page header titles the page" do
    get "/overview"
    assert_select "title", "All time · Chartlek"

    get "/overview/2024/3"
    assert_select "title", "March 2024 · Chartlek"

    get "/pace_trend"
    assert_select "title", "Pace Trends · Chartlek"
    assert_select "h1", /Performance/

    get "/pr_progress"
    assert_select "title", "PR Progress · Chartlek"
    assert_select "h1", /Performance/

    get "/runs", params: {year: "all"}
    assert_select "title", "Runs · All time · Chartlek"

    get "/runs", params: {year: 2024}
    assert_select "title", "Runs · 2024 · Chartlek"

    get "/overview/2024"
    assert_select "title", "2024 · Chartlek"

    get "/training_bands"
    assert_select "title", "Training Bands · Chartlek"

    get goal_path(Goal.create!(period: "month", starts_on: Date.new(2024, 3, 1), distance_km: 100))
    assert_select "title", "March 2024 goal · Chartlek"
  end

  test "a run page is titled with the run's name, escaped" do
    run = create(:activity, name: "<b>Long</b> & fast")

    get run_path(run)

    assert_select "title", text: "<b>Long</b> & fast · Chartlek"
  end

  test "the page is English" do
    get "/overview"

    assert_select "html[lang=en]"
  end

  test "an alert flash is announced as an alert and a notice as a status" do
    post gear_sync_path
    follow_redirect!
    assert_select "main"
    assert_select "p[role=alert]", /Reconnect Strava/
    assert_select "p[role=status]", false

    profile = Profile.instance
    profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    profile.update!(strava_scope: "activity:read_all,profile:read_all")
    post gear_sync_path
    follow_redirect!
    assert_select "p[role=status]", /Gear scan started/
    assert_select "p[role=alert]", false
  end

  test "the manifest is served as JSON and linked from every page" do
    get "/manifest.json"

    assert_response :success
    assert_equal "Chartlek", response.parsed_body["name"]

    get "/overview"

    assert_select "link[rel=manifest][href='/manifest.json']"
  end

  test "the four timeline pages share one window block wired to their own controller" do
    create(:activity, local_started_at: Time.utc(2024, 3, 5, 7), bands: {"pace" => [100] + [0] * 36, "hr" => [0, 0, 60, 0, 0], "grade" => nil})
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52)

    {"/pace_trend" => "pace-trends", "/pr_progress" => "pr-progress", "/wellness" => "wellness", "/training_bands" => "training-bands"}.each do |path, controller|
      get path

      assert_select "[data-#{controller}-target=range].font-semibold", 1, path
      assert_select "div", {text: "Pick a span or drag the timeline below to change the window.", count: 1}, path
      assert_select "[role=group][aria-label=Window] button[data-action='#{controller}#preset'][data-#{controller}-target=preset]", 5, path
      assert_select "[role=group][aria-label=Window] button", {text: "All time", count: 1}, path
      assert_select "[data-#{controller}-target=timeline]", 1, path
    end
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
