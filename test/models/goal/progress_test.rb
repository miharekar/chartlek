require "test_helper"

class Goal::ProgressTest < ActiveSupport::TestCase
  Run = Struct.new(:id, :local_started_at, :distance_m)

  def goal(km = 310, period: "month", on: Date.new(2026, 10, 1))
    Goal.new(period:, starts_on: on, distance_km: km).tap(&:valid?)
  end

  def ride(id, day, km, month: 10)
    Run.new(id, Time.utc(2026, month, day, 7), km * 1000.0)
  end

  def progress(runs, today:, goal: self.goal)
    Goal::Progress.new(goal, runs, today:)
  end

  test "a goal on pace is ahead and not behind" do
    result = progress([ride(1, 1, 10), ride(2, 2, 12), ride(3, 3, 8)], today: Date.new(2026, 10, 3))

    assert_equal [10.0, 22.0, 30.0], result.cumulative
    assert_equal 30.0, result.done_km
    assert_equal 30.0, result.expected_km
    assert_in_delta 0, result.ahead_km
    assert_not result.behind?
    assert_equal 29, result.days_left
    assert_in_delta 280.0 / 29, result.required_km_per_day
    assert_equal 10, result.percent
  end

  test "behind: shortfall, required per day and the catch-up ratio to the last 28 days" do
    result = progress([ride(1, 1, 10), ride(2, 5, 18)], today: Date.new(2026, 10, 10))

    assert result.behind?
    assert_in_delta(-62.0, result.ahead_km)
    assert_equal 22, result.days_left
    assert_in_delta 282.0 / 22, result.required_km_per_day
    assert_in_delta 28.0 / 28, result.recent_km_per_day
    assert_in_delta 282.0 / 22, result.catch_up_ratio
    assert_equal({ratio: 12.82}, result.payload[:catch_up])
  end

  test "until today has a run the expectation stops at yesterday" do
    runs = [ride(1, 1, 10), ride(2, 2, 10)]
    morning = progress(runs, today: Date.new(2026, 10, 3))
    after_short_run = progress(runs + [ride(3, 3, 5)], today: Date.new(2026, 10, 3))

    assert morning.open_today?
    assert_in_delta 20.0, morning.expected_km
    assert_in_delta 0, morning.ahead_km
    assert_not morning.behind?
    assert_not after_short_run.open_today?
    assert_in_delta 30.0, after_short_run.expected_km
    assert after_short_run.behind?
    assert_equal [true, false], [morning.payload[:open_today], after_short_run.payload[:open_today]]
  end

  test "the first morning of a period expects nothing" do
    result = progress([], today: Date.new(2026, 10, 1))

    assert_equal 0.0, result.expected_km
    assert_not result.behind?
  end

  test "recent average counts runs before the period too, and no recent runs gives no ratio" do
    before = progress([ride(1, 20, 56, month: 9)], today: Date.new(2026, 10, 2))
    none = progress([], today: Date.new(2026, 10, 2))

    assert_in_delta 2.0, before.recent_km_per_day
    assert_equal 0.0, none.recent_km_per_day
    assert none.behind?
    assert_nil none.catch_up_ratio
    assert_equal({ratio: nil}, none.payload[:catch_up])
  end

  test "same-day runs add up and the day links to the longest run" do
    result = progress([ride(1, 2, 5), ride(2, 2, 9), ride(3, 2, 1)], today: Date.new(2026, 10, 4))

    assert_equal [0.0, 15.0, 15.0, 15.0], result.cumulative
    assert_equal [{index: 1, km: 15.0, runs: 3, url: "/runs/2"}], result.daily
  end

  test "runs after today are ignored" do
    result = progress([ride(1, 2, 5), ride(2, 20, 9)], today: Date.new(2026, 10, 4))

    assert_equal 5.0, result.done_km
  end

  test "reaching the goal stops catch-up and the requirement" do
    result = progress([ride(1, 1, 120)], today: Date.new(2026, 10, 3), goal: goal(100))

    assert result.complete?
    assert_not result.behind?
    assert_equal 0.0, result.required_km_per_day
    assert_equal 0.0, result.remaining_km
    assert_nil result.payload[:catch_up]
  end

  test "a finished period is final and asks for nothing" do
    result = progress([ride(1, 1, 50)], today: Date.new(2026, 11, 5))

    assert_equal 31, result.elapsed_days
    assert_equal 0, result.days_left
    assert_nil result.required_km_per_day
    assert_not result.behind?
    assert_equal 16, result.percent
    assert_equal 260.0, result.remaining_km
    assert_not result.open_today?
    assert result.payload[:ended]
  end

  test "a period that has not started has no progress" do
    result = progress([], today: Date.new(2026, 9, 20))

    assert_equal 0, result.elapsed_days
    assert_equal [], result.cumulative
    assert_equal 0.0, result.done_km
    assert_equal 31, result.days_left
    assert_in_delta 10.0, result.required_km_per_day
    assert_not result.behind?
  end

  test "payload carries the start in UTC milliseconds" do
    payload = progress([ride(1, 1, 10)], today: Date.new(2026, 10, 1)).payload

    assert_equal Time.utc(2026, 10, 1).to_i * 1000, payload[:start]
    assert_equal [31, 310.0], [payload[:days], payload[:goal_km]]
  end
end
