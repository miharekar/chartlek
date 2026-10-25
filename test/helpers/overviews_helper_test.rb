require "test_helper"

class OverviewsHelperTest < ActionView::TestCase
  test "formats pace and duration" do
    assert_equal "6:14", overview_pace(374)
    assert_equal "4:00", overview_pace(239.6)
    assert_equal "24:23", overview_duration(1463)
    assert_equal "1:37:30", overview_duration(5850)
    assert_equal "3:20:32", overview_duration(12_032)
  end

  test "formats distance and dates" do
    assert_equal "12.3", overview_distance(12.34)
    assert_equal "21 Apr 2020", overview_date(Date.new(2020, 4, 21))
    assert_equal "21 Apr 2020", overview_date(Time.utc(2020, 4, 21, 5))
    assert_equal "21 Apr 2020", overview_range(Date.new(2020, 4, 21), Date.new(2020, 4, 21))
    assert_equal "21 Apr 2020 – 9 Aug 2020", overview_range(Date.new(2020, 4, 21), Date.new(2020, 8, 9))
  end

  test "period titles" do
    today = Date.new(2024, 3, 20)

    assert_equal "All time", overview_period_title(Overview::Period.new(year: nil, month: nil, today:, first_date: today))
    assert_equal "2023", overview_period_title(Overview::Period.new(year: 2023, month: nil, today:, first_date: today))
    assert_equal "March 2023", overview_period_title(Overview::Period.new(year: 2023, month: 3, today:, first_date: today))
  end

  test "older years are everything past the newest eight" do
    years = (2010..2024).to_a.reverse

    assert_equal 8, overview_visible_years(years).size
    assert_equal [2016, 2015, 2014, 2013, 2012, 2011, 2010], overview_older_years(years)
  end

  test "disabled pills are not links" do
    assert_includes overview_pill("Jan", "/x", :disabled), "<span"
    assert_includes overview_pill("Jan", "/x", :idle), 'href="/x"'
  end
end
