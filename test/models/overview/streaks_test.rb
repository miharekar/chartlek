require "test_helper"

class Overview::StreaksTest < ActiveSupport::TestCase
  TODAY = Date.new(2024, 3, 20)

  def dates(*days)
    days.map { Date.new(2024, 3, it) }
  end

  def streaks(run_days, **options)
    period = Overview::Period.new(year: options[:year], month: options[:month], today: TODAY, first_date: Date.new(2024, 3, run_days.min))
    Overview::Streaks.new(dates(*run_days), period)
  end

  test "longest streak and break" do
    s = streaks([1, 2, 3, 6, 7, 12, 13, 14, 15, 16])

    assert_equal [Date.new(2024, 3, 12), Date.new(2024, 3, 16), 5], [s.longest_streak.from, s.longest_streak.to, s.longest_streak.days]
    assert_equal [Date.new(2024, 3, 8), Date.new(2024, 3, 11), 4], [s.longest_break.from, s.longest_break.to, s.longest_break.days]
  end

  test "ties pick the earliest" do
    s = streaks([1, 2, 5, 6])

    assert_equal Date.new(2024, 3, 1), s.longest_streak.from
  end

  test "breaks start at the first run, not before" do
    s = streaks([5, 6, 7])

    assert_equal Date.new(2024, 3, 8), s.longest_break.from
  end

  test "current streak when running today" do
    s = streaks([17, 18, 19, 20])

    assert_equal [:streak, 4], [s.current.kind, s.current.days]
  end

  test "streak stays alive when today has no run yet" do
    s = streaks([17, 18, 19])

    assert_equal [:streak, Date.new(2024, 3, 19)], [s.current.kind, s.current.to]
  end

  test "current break after a gap" do
    s = streaks([10, 11, 12])

    assert_equal [:break, 8], [s.current.kind, s.current.days]
  end

  test "no current segment when the period does not include today" do
    assert_nil streaks([1, 2], year: 2023).current
  end

  test "streaks and breaks are clipped to the period" do
    runs = dates(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) + [Date.new(2024, 4, 1)]
    period = Overview::Period.new(year: 2024, month: 3, today: Date.new(2024, 4, 10), first_date: Date.new(2024, 3, 1))
    s = Overview::Streaks.new(runs + [Date.new(2024, 2, 20), Date.new(2024, 2, 21)], period)

    assert_equal Date.new(2024, 3, 1), s.longest_streak.from
    assert_equal Date.new(2024, 3, 10), s.longest_streak.to
    assert_equal Date.new(2024, 3, 31), s.longest_break.to
  end

  test "no break when every day has a run" do
    assert_nil streaks([18, 19, 20]).longest_break
  end
end
