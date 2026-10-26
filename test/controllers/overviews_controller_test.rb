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
    assert_select "table", text: /5 km/
    assert_select "p", text: /fifteen/i
    assert_select "a[href='/overview/2023']"
    assert_select "a[href='/overview/2024']"
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
    assert_includes response.body, "&lt;b&gt;Long"
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
end
