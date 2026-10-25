require "test_helper"

class SpiTest < ActiveSupport::TestCase
  BENCHMARK_DISTANCES = PersonalRecords::BENCHMARKS.map(&:last)

  test "1970 world records score close to the 1035 points the running curve was fitted to" do
    {
      "800 m Snell 1:44.3" => [800, "1:44.3"],
      "1500 m Ryun 3:33.1" => [1500, "3:33.1"],
      "5000 m Clarke 13:16.6" => [5000, "13:16.6"],
      "10000 m Clarke 27:39.4" => [10000, "27:39.4"],
      "marathon Clayton 2:08:33.6" => [42195, "2:08:33.6"]
    }.each do |name, (distance_m, time)|
      assert_in_delta 1035, Spi.points(distance_m, seconds(time)), 60, name
    end
  end

  test "points track the published Gardner-Purdy 1970 table" do
    {
      5000 => {1000 => "13:33.8", 400 => "20:38.2", 200 => "24:58.7"},
      10000 => {1000 => "28:24.2", 400 => "43:31.6", 200 => "52:55.2"},
      20000 => {1000 => "59:30", 400 => "1:31:50", 200 => "1:52:08"}
    }.each do |distance_m, table|
      table.each do |points, time|
        assert_in_delta points, Spi.points(distance_m, seconds(time)), 30, "#{distance_m} m in #{time}"
      end
    end
  end

  test "points and SPI are pinned for synthetic performances" do
    assert_in_delta(-310.0879, Spi.points(5000, 3600), 0.01)

    {
      [10_000, 2700] => [366.5232, 516.9459],
      [42_195, 12_600] => [428.3210, 564.0695],
      [1500, 300] => [532.1838, 643.2694]
    }.each do |(distance_m, time), (points, spi)|
      assert_in_delta points, Spi.points(distance_m, time), 0.01, "points at #{distance_m} m in #{time} s"
      assert_in_delta spi, Spi.for(distance_m, time), 0.01, "SPI at #{distance_m} m in #{time} s"
    end
  end

  test "walking 5 km in an hour is SPI 1" do
    assert_operator Spi.points(5000, 3600), :<, 0
    assert_in_delta 1, Spi.for(5000, 3600), 1e-9
  end

  test "SPI is clamped to 1..1000" do
    assert_equal 1000, Spi.for(5000, 600)
    assert_equal 1, Spi.for(5000, 20_000)
  end

  test "SPI is nil under 400 m or without a positive time" do
    assert_nil Spi.for(399.9, 60)
    assert_nil Spi.for(5000, 0)
    assert_nil Spi.for(5000, -1)
    assert_not_nil Spi.for(400, 120)
  end

  test "faster runs score higher" do
    assert_operator Spi.for(10_000, 2400), :>, Spi.for(10_000, 2700)
    assert_operator Spi.for(10_000, 2700), :>, 1
  end

  test "time_for inverts for at every benchmark distance" do
    BENCHMARK_DISTANCES.each do |distance_m|
      [100, 400, 650, 900].each do |spi|
        assert_in_delta spi, Spi.for(distance_m, Spi.time_for(distance_m, spi)), 1e-6
      end
    end
  end

  test "time_for gets shorter as SPI rises" do
    assert_operator Spi.time_for(10_000, 600), :<, Spi.time_for(10_000, 500)
  end

  test "time_for scales with distance at constant SPI" do
    assert_operator Spi.time_for(5000, 500), :<, Spi.time_for(10_000, 500)
    assert_operator Spi.time_for(10_000, 500), :<, Spi.time_for(42_195, 500)
  end

  test "time_table covers SPI 1 to 1000 in ascending order" do
    table = Spi.time_table(10_000)

    assert_equal [1, 1000], [table.first.first, table.last.first]
    assert_equal table.map(&:first).sort, table.map(&:first)
    assert_equal table.map(&:last).sort.reverse, table.map(&:last)
  end

  test "time_table rows are pinned" do
    rows = Spi.time_table(10_000).to_h.transform_keys(&:to_f)

    {1.0 => 7707.8, 100.0 => 5684.7, 300.0 => 3714.9, 500.0 => 2758.9, 1000.0 => 1678.8}.each do |spi, time|
      assert_in_delta time, rows[spi], 0.01, "SPI #{spi}"
    end
  end

  test "interpolating time_table stays within 0.5 s of time_for" do
    ([5000, 10_000, 21_097.5, 42_195] + BENCHMARK_DISTANCES).uniq.each do |distance_m|
      table = Spi.time_table(distance_m)

      table.each_cons(2) do |(x0, y0), (x1, y1)|
        spi = (x0 + x1) / 2.0
        assert_in_delta Spi.time_for(distance_m, spi), (y0 + y1) / 2, 0.5, "SPI #{spi} at #{distance_m} m"
      end
    end
  end

  private
  def seconds(text)
    text.split(":").map(&:to_f).inject { |total, part| total * 60 + part }
  end
end
