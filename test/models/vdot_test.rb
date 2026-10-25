require "test_helper"

class VdotTest < ActiveSupport::TestCase
  DANIELS_TABLE = {
    50 => {5000 => "19:57", 10000 => "41:21", 21097.5 => "1:31:35", 42195 => "3:10:49"},
    40 => {5000 => "24:08", 10000 => "50:03", 21097.5 => "1:50:59", 42195 => "3:49:45"}
  }

  test "time_for matches Daniels' published tables" do
    DANIELS_TABLE.each do |vdot, times|
      times.each do |distance_m, time|
        assert_in_delta seconds(time), Vdot.time_for(distance_m, vdot), 10, "VDOT #{vdot} at #{distance_m} m"
      end
    end
  end

  test "for matches Daniels' published tables" do
    DANIELS_TABLE.each do |vdot, times|
      times.each do |distance_m, time|
        assert_in_delta vdot, Vdot.for(distance_m, seconds(time)), 0.15, "#{time} at #{distance_m} m"
      end
    end
  end

  test "time_for inverts for" do
    [3000, 10_000, 21_097.5, 42_195].each do |distance_m|
      assert_in_delta 45, Vdot.for(distance_m, Vdot.time_for(distance_m, 45)), 1e-6
    end
  end

  test "nil under 400 m or without a positive time" do
    assert_nil Vdot.for(399.9, 60)
    assert_nil Vdot.for(5000, 0)
    assert_not_nil Vdot.for(400, 120)
  end

  test "faster runs score higher" do
    assert_operator Vdot.for(5000, 1200), :>, Vdot.for(5000, 1500)
  end

  test "time_table covers VDOT 10 to 90 in ascending order" do
    table = Vdot.time_table(10_000)

    assert_equal [10, 90], [table.first.first, table.last.first]
    assert_equal table.map(&:first).sort, table.map(&:first)
    assert_equal table.map(&:last).sort.reverse, table.map(&:last)
  end

  test "time_table rows are pinned" do
    rows = Vdot.time_table(10_000).to_h.transform_keys(&:to_f)

    {10.0 => 8813.3, 30.0 => 3828.9, 50.0 => 2479.6, 90.0 => 1505.1}.each do |vdot, time|
      assert_in_delta time, rows[vdot], 0.01, "VDOT #{vdot}"
    end
  end

  test "interpolating time_table stays within 1 s of time_for" do
    ([5000, 10_000, 21_097.5, 42_195] + PersonalRecords::BENCHMARKS.map(&:last)).uniq.each do |distance_m|
      table = Vdot.time_table(distance_m)

      table.each_cons(2) do |(x0, y0), (x1, y1)|
        vdot = (x0 + x1) / 2.0
        assert_in_delta Vdot.time_for(distance_m, vdot), (y0 + y1) / 2, 1, "VDOT #{vdot} at #{distance_m} m"
      end
    end
  end

  private
  def seconds(text)
    text.split(":").map(&:to_f).inject { |total, part| total * 60 + part }
  end
end
