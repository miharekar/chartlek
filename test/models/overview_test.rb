require "test_helper"

class OverviewTest < ActiveSupport::TestCase
  TODAY = Date.new(2024, 3, 20)

  def run_on(time, **attrs)
    build(:activity, local_started_at: Time.utc(*time), started_at: Time.utc(*time), **attrs)
  end

  def overview(runs, **options)
    Overview.new(runs, today: TODAY, **options)
  end

  def sample
    [
      run_on([2024, 3, 4, 7, 0], distance_m: 10_000, timer_s: 3000),
      run_on([2024, 3, 6, 18, 0], distance_m: 5000, timer_s: 1800),
      run_on([2024, 3, 9, 12, 0], distance_m: 21_000, timer_s: 7200),
      run_on([2024, 3, 9, 8, 0], distance_m: 4000, timer_s: 1200),
      run_on([2024, 3, 19, 6, 0], distance_m: 10_000, timer_s: 3300)
    ]
  end

  test "totals and averages" do
    o = overview(sample)

    assert_equal 5, o.count
    assert_in_delta 50, o.total_km, 1e-9
    assert_in_delta 10, o.average_km, 1e-9
    assert_in_delta 16_500 / 50.0, o.average_pace, 1e-9
    assert_equal "fifty", o.total_km_in_words
    assert_equal 21_000, o.longest.distance_m
  end

  test "weekday stats" do
    o = overview(sample)

    assert_equal 7, o.weekdays.size
    assert_equal "Saturday", o.most_often.name
    assert_equal 2, o.most_often.count
    assert_in_delta 12.5, o.most_often.average_km, 1e-9
    assert_equal 0, o.least_often.count
    assert_equal 0.0, o.least_often.average_km
  end

  test "days per week uses distinct days over the period" do
    o = overview(sample)

    assert_equal 4, o.days_run
    assert_in_delta 4 / (17 / 7.0), o.days_per_week, 1e-9
  end

  test "days per week for a year view is cut off at today" do
    o = overview(sample, year: 2024)

    assert_in_delta 4 / (80 / 7.0), o.days_per_week, 1e-9
  end

  test "am pm split counts noon as pm" do
    o = overview(sample)

    assert_equal 2, o.pm_count
    assert_equal 40, o.pm_percent
  end

  test "period filters runs and keeps others for trailing" do
    runs = sample + [run_on([2023, 12, 1, 7, 0], distance_m: 8000, timer_s: 2400)]

    assert_equal 5, overview(runs, year: 2024).count
    assert_equal 1, overview(runs, year: 2023).count
    assert_equal 5, overview(runs, year: 2024, month: 3).count
    assert_equal 6, overview(runs).count
  end

  test "empty without runs in the period" do
    assert overview([]).empty?
    assert overview(sample, year: 2020).empty?
  end

  test "today moves forward for runs dated after the server date" do
    travel_to Time.utc(2024, 3, 20, 23) do
      run = run_on([2024, 3, 21, 0, 30], started_at: Time.utc(2024, 3, 20, 23, 30))
      run.save!
      o = Overview.new([run])

      assert_equal Date.new(2024, 3, 21), o.period.last
      assert_equal 1, o.count
    end
  end

  test "years newest first and always include the selected one" do
    runs = [run_on([2022, 5, 1, 7, 0]), run_on([2024, 3, 1, 7, 0])]

    assert_equal [2024, 2022], overview(runs).years.reject { it == 2023 }
    assert_includes overview(runs).years(2010), 2010
    assert_equal [3], overview(runs).months_with_runs(2024)
  end

  test "records come from the period's runs" do
    o = overview([run_on([2024, 3, 4, 7, 0], distance_m: 5100, timer_s: 1500)])

    assert_equal ["5 km"], o.records.map(&:name)
  end
end
