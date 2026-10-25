require "test_helper"

class Overview::PeriodTest < ActiveSupport::TestCase
  TODAY = Date.new(2024, 3, 20)

  def period(**options)
    Overview::Period.new(year: nil, month: nil, today: TODAY, first_date: Date.new(2023, 1, 1), **options)
  end

  test "all time runs from the first run to today" do
    p = period

    assert p.all_time?
    assert_equal Date.new(2023, 1, 1)..TODAY, p.range
    assert_equal 365, p.trailing_days
    assert_equal :month, p.granularity
    assert p.includes_today?
  end

  test "year covers the calendar year cut off at today" do
    p = period(year: 2024)

    assert_equal Date.new(2024, 1, 1)..TODAY, p.range
    assert_equal 80, p.days
    assert_equal 90, p.trailing_days
    assert_equal :week, p.granularity
  end

  test "past periods are complete and do not include today" do
    year = period(year: 2023)
    month = period(year: 2023, month: 2)

    assert_equal 365, year.days
    assert_equal 28, month.days
    assert_equal 7, month.trailing_days
    assert_equal :day, month.granularity
    assert_not month.includes_today?
  end

  test "future periods are empty" do
    assert_equal 0, period(year: 2030).days
  end
end
