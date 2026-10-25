require "test_helper"

class Overview::BarsTest < ActiveSupport::TestCase
  TODAY = Date.new(2024, 3, 20)

  def run_on(time, **attrs)
    build(:activity, id: (@next_id = (@next_id || 0) + 1), local_started_at: Time.utc(*time), started_at: Time.utc(*time), **attrs)
  end

  def buckets(runs, **options)
    Overview.new(runs, today: TODAY, **options).bars[:buckets]
  end

  def runs
    @runs ||= [
      run_on([2024, 2, 5, 7, 0], distance_m: 10_000, timer_s: 3000, elevation_gain_m: 100, spi: 500),
      run_on([2024, 2, 7, 7, 0], distance_m: 5000, timer_s: 1500, elevation_gain_m: nil, spi: 400),
      run_on([2024, 3, 3, 7, 0], distance_m: 8000, timer_s: 2400, elevation_gain_m: 50, spi: nil)
    ]
  end

  test "all time buckets by month including empty ones" do
    result = Overview.new(runs + [run_on([2023, 12, 10, 7, 0])], today: TODAY).bars
    months = result[:buckets]

    assert_equal :month, result[:granularity]
    assert_equal %w[2023-12-01 2024-01-01 2024-02-01 2024-03-01], months.pluck(:from)
    assert_equal 0, months[1][:runs]
    assert_equal 0, months[1][:distance]
    assert_nil months[1][:avg_pace]
    assert_nil months[1][:href]
  end

  test "month bucket metrics" do
    february = buckets(runs)[0]

    assert_equal 2, february[:runs]
    assert_in_delta 15, february[:distance], 1e-9
    assert_equal 100, february[:elevation]
    assert_in_delta 7.5, february[:avg_distance], 1e-9
    assert_in_delta 300, february[:avg_pace], 1e-9
    assert_in_delta 450, february[:avg_spi], 1e-9
    assert_equal "/overview/2024/2", february[:href]
  end

  test "spi average ignores runs without one" do
    assert_nil buckets(runs)[1][:avg_spi]
  end

  test "year view buckets by monday-start week" do
    weeks = buckets(runs, year: 2024)

    assert_equal "2024-01-01", weeks.first[:from]
    assert_equal "2024-03-18", weeks.last[:from]
    week = weeks.find { it[:from] == "2024-02-05" }
    assert_equal 2, week[:runs]
    assert_equal "/overview/2024/2", week[:href]
  end

  test "week bar links to the month of its monday" do
    runs = [run_on([2024, 4, 2, 7, 0])]
    week = Overview.new(runs, year: 2024, today: Date.new(2024, 4, 30)).bars[:buckets].find { it[:from] == "2024-04-01" }
    wednesday = Overview.new([run_on([2024, 1, 31, 7, 0])], year: 2024, today: TODAY).bars[:buckets].find { it[:from] == "2024-01-29" }

    assert_equal "/overview/2024/4", week[:href]
    assert_equal "/overview/2024/1", wednesday[:href]
  end

  test "the first week bar of a year links into that year" do
    week = Overview.new([run_on([2023, 1, 1, 7, 0])], year: 2023, today: Date.new(2023, 6, 1)).bars[:buckets].first

    assert_equal "2022-12-26", week[:from]
    assert_equal "/overview/2023/1", week[:href]
  end

  test "month view buckets by day and links to the first run" do
    days = buckets(runs, year: 2024, month: 2)

    assert_equal 29, days.size
    assert_equal 1, days[4][:runs]
    assert_equal "/runs/#{runs.first.id}", days[4][:href]
    assert_nil days[0][:href]
  end

  test "several runs on a day link to the first one" do
    morning = run_on([2024, 3, 3, 7, 0])
    evening = run_on([2024, 3, 3, 19, 0])
    day = buckets([evening, morning], year: 2024, month: 3)[2]

    assert_equal 2, day[:runs]
    assert_equal "/runs/#{morning.id}", day[:href]
  end
end
