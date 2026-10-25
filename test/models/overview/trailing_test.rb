require "test_helper"

class Overview::TrailingTest < ActiveSupport::TestCase
  TODAY = Date.new(2024, 3, 20)

  def run_on(day, km)
    time = Time.utc(2024, 3, day, 7, 0)
    build(:activity, local_started_at: time, started_at: time, distance_m: km * 1000, timer_s: km * 300)
  end

  def points(runs, **options)
    Overview.new(runs, today: TODAY, **options).trailing
  end

  test "month view uses a 7 day window including runs before the period" do
    runs = [run_on(1, 10), run_on(3, 5)]
    month = Overview.new(runs + [build(:activity, local_started_at: Time.utc(2024, 2, 29, 7), started_at: Time.utc(2024, 2, 29, 7), distance_m: 20_000, timer_s: 6000)], year: 2024, month: 3, today: TODAY).trailing
    sums = month[:points].to_h

    assert_equal 7, month[:days]
    assert_equal 20 + 10, sums["2024-03-01"]
    assert_equal 35, sums["2024-03-03"]
    assert_equal 35, sums["2024-03-05"]
    assert_equal 35, sums["2024-03-06"]
    assert_equal 15, sums["2024-03-07"]
    assert_equal 5, sums["2024-03-08"]
    assert_equal 0, sums["2024-03-10"]
  end

  test "all time starts at the first run with a 365 day window" do
    result = points([run_on(1, 10), run_on(3, 5)])

    assert_equal 365, result[:days]
    assert_equal ["2024-03-01", 10.0], result[:points].first
    assert_equal ["2024-03-20", 15.0], result[:points].last
  end

  test "year view covers january to today with a 90 day window" do
    result = points([run_on(1, 10)], year: 2024)

    assert_equal 90, result[:days]
    assert_equal "2024-01-01", result[:points].first.first
    assert_equal 10.0, result[:points].last.last
  end
end
