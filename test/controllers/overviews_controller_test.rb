require "test_helper"

class OverviewsControllerTest < ActionDispatch::IntegrationTest
  def create_runs
    create(:activity, local_started_at: Time.utc(2023, 5, 6, 7), started_at: Time.utc(2023, 5, 6, 7), distance_m: 10_000, timer_s: 3000, name: "<b>Long</b>")
    create(:activity, local_started_at: Time.utc(2024, 3, 5, 18), started_at: Time.utc(2024, 3, 5, 18), distance_m: 5100, timer_s: 1500, race: true)
  end

  test "renders with data" do
    create_runs

    get "/overview"

    assert_response :success
    assert_select "[data-controller='period-bars']"
    assert_select "[data-controller='trailing-line']"
    assert_select "[data-controller='pace-scatter']"
    assert_select "[data-controller='heatmap']"
    assert_select "[role=group][aria-label=Metric] button[data-action='period-bars#metric']", count: 5
    assert_select "button[value=distance][aria-pressed=true]", "Distance"
    assert_select "[data-period-bars-target=title]", /Distance per/
    assert_select "[role=group][aria-label=Metric] button[data-action='pace-scatter#metric']", count: 3
    assert_select "select", false
    assert_select "table", text: /5 km/
    assert_select "p", text: /fifteen/i
    assert_select "a[href='/overview/2023']"
    assert_select "a[href='/overview/2024']"
  end

  test "compresses the response when the client accepts gzip" do
    create_runs

    get "/overview", headers: {"Accept-Encoding" => "gzip"}

    assert_equal "gzip", response.headers["content-encoding"]
  end

  test "links to the latest run on every period" do
    create_runs
    latest = Activity.order(:local_started_at).last

    ["/overview", "/overview/2023"].each do |path|
      get path

      assert_select "a[href='/runs/#{latest.id}']", text: "Latest run · 5 Mar · 5.1 km →"
    end
  end

  test "period selector lists every year without a dropdown" do
    (2010..2024).each { |year| create(:activity, local_started_at: Time.utc(year, 5, 6, 7), started_at: Time.utc(year, 5, 6, 7)) }

    get "/overview"

    assert_select "nav[aria-label='Period'] a", text: "2010"
    assert_select "nav[aria-label='Period'] a", text: "2024"
    assert_select "details", false
  end

  test "renders an empty state without data" do
    get "/overview"

    assert_response :success
    assert_select "[data-controller='period-bars']", false
    assert_select "a", text: /Latest run/, count: 0
    assert_select "p", text: /No runs/
  end

  test "year view shows a month selector with empty months disabled" do
    create_runs

    get "/overview/2024"

    assert_response :success
    assert_select "[data-controller='heatmap']"
    assert_select "nav[aria-label='Month'] a", text: "Mar"
    assert_select "nav[aria-label='Month'] span", text: "Apr"
  end

  test "month view renders and escapes data" do
    create_runs

    get "/overview/2023/5"

    assert_response :success
    assert_select "section", text: /Daily stats for May 2023/
    assert_includes response.body, "\\u003cb\\u003eLong"
    assert_not_includes response.body, "<b>Long</b>"
  end

  test "period without runs shows the empty state" do
    create_runs

    get "/overview/2023/6"

    assert_response :success
    assert_select "p", text: /No runs/
  end

  test "query params cannot select or break the period" do
    create_runs

    ["/overview?year=2020&month=13", "/overview?month=3", "/overview?year[]=1"].each do |path|
      get path

      assert_response :success
      assert_select "[data-controller='period-bars']"
    end
  end

  test "the chart payloads carry what the linked hover needs" do
    create(:activity, local_started_at: Time.utc(2024, 3, 5, 18), started_at: Time.utc(2024, 3, 5, 18), distance_m: 5100, timer_s: 1500, elevation_gain_m: 41.6)
    create(:activity, local_started_at: Time.utc(2024, 3, 7, 7), started_at: Time.utc(2024, 3, 7, 7), distance_m: 10_000, timer_s: 3000, elevation_gain_m: nil)

    get "/overview/2024/3"

    scatter = JSON.parse(css_select("[data-controller='pace-scatter']").first["data-pace-scatter-data-value"])
    assert_equal [Time.utc(2024, 3, 5, 18).to_i * 1000, Time.utc(2024, 3, 7, 7).to_i * 1000], scatter["runs"].pluck("t")
    assert_equal [42, nil], scatter["runs"].pluck("elev")
    assert_equal [5.1, 10.0], scatter["runs"].pluck("km")

    heatmap = JSON.parse(css_select("[data-controller='heatmap']").first["data-heatmap-data-value"])
    assert_equal 1, heatmap["step"]
    assert_equal Time.utc(2024, 3, 1).to_i * 1000, heatmap["cells"].first["from"]
    assert heatmap["cells"].all? { it["from"] % 86_400_000 == 0 }

    get "/overview"
    weekly = JSON.parse(css_select("[data-controller='heatmap']").first["data-heatmap-data-value"])
    assert_equal 7, weekly["step"]
    assert_equal [1], weekly["cells"].pluck("from").map { Time.at(it / 1000).utc.wday }.uniq
  end

  test "the streak segments expose their span for the linked hover" do
    create(:activity, local_started_at: Time.utc(2024, 3, 5, 7), started_at: Time.utc(2024, 3, 5, 7))
    create(:activity, local_started_at: Time.utc(2024, 3, 6, 7), started_at: Time.utc(2024, 3, 6, 7))

    get "/overview/2024/3"

    assert_select "[data-controller=streaks] [data-from='2024-03-05'][data-to='2024-03-06'][data-action*='streaks#select']"
    assert_select "[data-controller=streaks] [data-action*='streaks#clear']", minimum: 1
  end

  def with_march_run
    travel_to Time.utc(2024, 3, 20, 12) do
      create(:activity, local_started_at: Time.utc(2024, 3, 5, 7), started_at: Time.utc(2024, 3, 5, 7), distance_m: 31_000)
      yield
    end
  end

  test "the monthly goal widget sits above the grid and the yearly slot nudges" do
    with_march_run do
      goal = Goal.create!(period: "month", starts_on: Date.new(2024, 3, 1), distance_km: 93)

      get "/overview"

      assert_select "div.mt-6.flex section a[href=?]", goal_path(goal), text: "March 2024 goal"
      assert_select "[role=progressbar][aria-valuenow='33']", count: 1
      assert_select "section", text: /31\.0of 93\.0 km/
      assert_select "section", text: /km behind/
      assert_select "section", text: /needed/
      assert_select ".grid section a[href=?]", new_goal_path(period: "year", starts_on: "2024-01-01"), text: "Set a yearly goal"
      assert_select "a", text: "Set a monthly goal", count: 0
    end
  end

  test "the yearly goal is a tile in the stats grid and not in the row above it" do
    with_march_run do
      goal = Goal.create!(period: "year", starts_on: Date.new(2024, 1, 1), distance_km: 900)

      get "/overview"

      assert_select ".grid section.col-span-2 a[href=?]", goal_path(goal), text: "2024 goal"
      assert_select "div.mt-6.flex", false
      assert_select "[role=progressbar]", count: 1
      assert_select "section.col-span-2.lg\\:col-span-4", false
      assert_select "a", text: /Set a/, count: 0
      assert_select "h2", text: "Longest run", count: 0

      get "/overview/2024"

      assert_select ".grid section a[href=?]", goal_path(goal)
    end
  end

  test "a month view has no yearly tile and the kilometers tile fills the row" do
    with_march_run do
      Goal.create!(period: "year", starts_on: Date.new(2024, 1, 1), distance_km: 900)

      get "/overview/2024/3"

      assert_select "[role=progressbar]", false
      assert_select "section.col-span-2.lg\\:col-span-4 h2", text: "Kilometers run"
      assert_select "a", text: /Set a yearly/, count: 0
    end
  end

  test "a past year without a goal drops the slot, the current year without one shows a quiet tile" do
    with_march_run do
      create(:activity, local_started_at: Time.utc(2023, 5, 6, 7), started_at: Time.utc(2023, 5, 6, 7))

      get "/overview/2023"

      assert_select "section.col-span-2.lg\\:col-span-4 h2", text: "Kilometers run"
      assert_select "a", text: /Set a/, count: 0

      get "/overview/2024"

      assert_select ".grid section.col-span-2 p", text: /No goal for 2024/
      assert_select ".grid a[href=?]", new_goal_path(period: "year", starts_on: "2024-01-01"), text: "Set a yearly goal"
    end
  end

  test "the monthly set-a-goal link shows only while neither the current month nor the current year has a goal" do
    with_march_run do
      get "/overview"

      assert_select "div.mt-6.flex a[href=?]", new_goal_path(period: "month", starts_on: "2024-03-01"), text: "Set a monthly goal"

      Goal.create!(period: "year", starts_on: Date.new(2024, 1, 1), distance_km: 900)
      get "/overview"

      assert_select "a", text: "Set a monthly goal", count: 0
    end
  end

  test "the overview works with no goals at all" do
    create_runs

    get "/overview/2024/3"

    assert_response :success
    assert_select "[role=progressbar]", false
  end
end
