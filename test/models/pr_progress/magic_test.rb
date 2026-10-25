require "test_helper"

class PrProgress::MagicTest < ActiveSupport::TestCase
  def record(name, distance_m, time_s)
    PersonalRecords::Record.new(name:, distance_m:, activity: nil, time_s:, pace: time_s / distance_m * 1000, speed_kmh: 0, count: 1, race: false)
  end

  def target(name, distance_m, time_s)
    PrProgress::Magic.target_for(record(name, distance_m, time_s))
  end

  test "rounds down to the next minute up to 5 km" do
    assert_equal 1440, target("5 km", 5000, 1463).target_s
    assert_equal 120, target("1 mi", 1609.344, 150).target_s
  end

  test "an exact step goes one step lower" do
    assert_equal 1380, target("5 km", 5000, 1440).target_s
    assert_equal 3300, target("10 km", 10_000, 3600).target_s
  end

  test "uses 5 minute steps above 5 km up to and including the half marathon" do
    assert_equal 5700, target("Half marathon", 21_097.5, 5850).target_s
    assert_equal 2400, target("10 km", 10_000, 2565).target_s
    assert_equal 1500, target("4 mi", 6437.376, 1520).target_s
  end

  test "uses 15 minute steps beyond the half marathon" do
    assert_equal 11_700, target("Marathon", 42_195, 12_032).target_s
    assert_equal 9000, target("40 km", 40_000, 9500).target_s
  end

  test "step boundaries" do
    assert_equal 1500, target("5 km", 5000, 1560).target_s
    assert_equal 1500, target("4 mi", 6437.376, 1501).target_s
  end

  test "computes the gap in seconds and percent" do
    result = target("Marathon", 42_195, 12_032)

    assert_equal 332, result.gap_s
    assert_in_delta 2.759, result.percent, 0.001
    assert_equal 12_032, result.pr_s
  end

  test "skips a PR faster than one step" do
    assert_nil target("1 mi", 1609.344, 59)
  end

  test "keeps the three smallest gaps in order" do
    records = [record("1 mi", 1609.344, 330), record("3 km", 3000, 700), record("5 km", 5000, 1475), record("10 km", 10_000, 3010), record("Marathon", 42_195, 12_032)]

    targets = PrProgress::Magic.for(records)

    assert_equal ["10 km", "5 km", "Marathon"], targets.map(&:name)
    assert_equal [0.33, 2.37, 2.76], targets.map { it.percent.round(2) }
  end

  test "ties keep benchmark order" do
    records = [record("5 km", 5000, 1470), record("3 km", 3000, 735), record("1 mi", 1609.344, 330)]

    assert_equal ["5 km", "3 km", "1 mi"], PrProgress::Magic.for(records).map(&:name)
  end

  test "limits to three" do
    records = PersonalRecords::BENCHMARKS.map { |name, meters| record(name, meters, 3700.0) }

    assert_equal 3, PrProgress::Magic.for(records).size
  end
end
