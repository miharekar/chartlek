require "test_helper"

class GoalsControllerTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.utc(2026, 10, 15, 12) }

  def goal(km: 150, on: Date.new(2026, 10, 1), period: "month")
    Goal.create!(period:, starts_on: on, distance_km: km)
  end

  def run_on(day, km: 10)
    create(:activity, started_at: Time.utc(2026, 10, day, 7), local_started_at: Time.utc(2026, 10, day, 7), distance_m: km * 1000.0)
  end

  test "index lists goals with their progress" do
    run_on(2)
    goal(km: 150)

    get goals_path

    assert_response :success
    assert_select "a[href=?]", goal_path(Goal.last), text: "October 2026"
    assert_select "td", text: "150.0 km"
    assert_select "a[href=?]", new_goal_path, text: "New goal"
  end

  test "index without goals shows an empty state" do
    get goals_path

    assert_select "p", text: "No goals yet."
    assert_select "table", false
  end

  test "show renders the chart payload and the tiles" do
    first = run_on(2)
    goal

    get goal_path(Goal.last)

    assert_response :success
    assert_select "[data-controller='goal-progress']"
    payload = JSON.parse(css_select("[data-controller='goal-progress']").first["data-goal-progress-data-value"])
    assert_equal 31, payload["days"]
    assert_equal 150.0, payload["goal_km"]
    assert_equal first.id, payload["daily"].first["url"][%r{\d+\z}].to_i
    assert_select "form[action=?]", goal_path(Goal.last) do
      assert_select "button", text: "Delete"
    end
    assert_select "a[href=?]", edit_goal_path(Goal.last)
  end

  test "new and create" do
    get new_goal_path(period: "year", starts_on: "2026-03-04")

    assert_select "input[name='goal[period]'][value=year][checked]"
    assert_select "input[name='goal[starts_on]'][value='2026-03-04']"
    assert_select "input[type=submit][value='Create goal']"

    assert_difference -> { Goal.count }, 1 do
      post goals_path, params: {goal: {period: "month", starts_on: "2026-10-17", distance_km: "120.5"}}
    end

    created = Goal.last
    assert_redirected_to goal_path(created)
    assert_equal [Date.new(2026, 10, 1), 120_500.0], [created.starts_on, created.distance_m]
  end

  test "create with invalid data re-renders with errors" do
    assert_no_difference -> { Goal.count } do
      post goals_path, params: {goal: {period: "month", starts_on: "2026-10-01", distance_km: ""}}
    end

    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: /Distance/
  end

  test "duplicate period and start is rejected" do
    goal

    post goals_path, params: {goal: {period: "month", starts_on: "2026-10-20", distance_km: "10"}}

    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: /Starts on has already been taken/
  end

  test "edit and update" do
    existing = goal

    get edit_goal_path(existing)
    assert_select "input[name='goal[distance_km]'][value='150.0']"
    assert_select "input[type=submit][value='Update goal']"

    patch goal_path(existing), params: {goal: {distance_km: "175"}}

    assert_redirected_to goal_path(existing)
    assert_equal 175_000.0, existing.reload.distance_m
  end

  test "update with invalid data re-renders" do
    existing = goal

    patch goal_path(existing), params: {goal: {distance_km: "0"}}

    assert_response :unprocessable_content
    assert_equal 150_000.0, existing.reload.distance_m
  end

  test "update with a blank start date re-renders the edit page" do
    existing = goal

    patch goal_path(existing), params: {goal: {starts_on: ""}}

    assert_response :unprocessable_content
    assert_select "h1", text: "Edit goal"
    assert_equal Date.new(2026, 10, 1), existing.reload.starts_on
  end

  test "destroy" do
    existing = goal

    assert_difference -> { Goal.count }, -1 do
      delete goal_path(existing)
    end

    assert_redirected_to goals_path
  end
end
