require "test_helper"

class Track::ElevationTest < ActiveSupport::TestCase
  def bins(points)
    rows = points.each_with_index.map { |(d, alt), index| {t: index.to_f, d: d.to_f, alt:} }
    Track::Elevation.new(rows).bins
  end

  test "a bin retains both climb and descent rather than net change" do
    result = bins([[0, 100], [25, 105], [50, 100], [100, 100]])

    assert_equal [{distance: 100.0, gain: 5.0, loss: 5.0}], result
  end

  test "threshold carries across boundaries and a climb lands where it passes the threshold" do
    result = bins([[0, 100], [100, 100.6], [200, 101.2], [250, 101.2]])

    assert_equal 0, result[0][:gain]
    assert_in_delta 1.2, result[1][:gain], 1e-9
    assert_equal 0, result[2][:gain]
    assert_equal [100.0, 100.0, 50.0], result.pluck(:distance)
    assert_in_delta 1.2, result.sum { it[:gain] }, 1e-9
  end

  test "noise and flat segments do not invent changes" do
    result = bins([[0, 100], [20, 100.6], [40, 99.8], [60, 100.9], [80, 100], [100, 100], [150, 100]])

    assert_equal [0, 0], result.pluck(:gain)
    assert_equal [0, 0], result.pluck(:loss)
  end

  test "missing elevation resets the threshold and is not bridged" do
    result = bins([[0, 100], [100, 105], [200, nil], [300, 150], [350, 154], [400, nil]])

    assert_equal [5.0, nil, nil, 4.0], result.pluck(:gain)
    assert_equal [nil, true, true, true], result.pluck(:missing)
    assert_equal [0.0, nil, nil, 0.0], result.pluck(:loss)
  end

  test "absent elevation stays absent" do
    assert_nil bins([[0, nil], [100, nil]])
    assert_nil bins([[0, 100], [100, nil]])
  end

  test "a climb spanning a km boundary and a partial bin keeps the entire change" do
    result = bins([[0, 100], [950, 100], [1050, 110], [1125, 110]])

    assert_equal 12, result.size
    assert_equal 25, result.last[:distance]
    assert_in_delta 5, result[9][:gain], 1e-9
    assert_in_delta 5, result[10][:gain], 1e-9
    assert_in_delta 10, result.sum { it[:gain] }, 1e-9
  end

  test "a segment overlapping a bin by a float-fuzz length does not touch that bin" do
    result = bins([[0, 100], [100.0000001, 100], [200, nil]])

    assert_equal [0.0, nil], result.pluck(:gain)
    assert_equal [nil, true], result.pluck(:missing)
  end

  test "a stationary row on a boundary does not mark the next bin missing" do
    result = bins([[0, 100], [100, 100], [100, nil], [100, 100], [200, 100]])

    assert_equal [0.0, 0.0], result.pluck(:gain)
    assert_equal [nil, nil], result.pluck(:missing)
  end

  test "a climb accepted on a stationary row lands in the bin it stopped in" do
    result = bins([[0, 100], [50, 100], [50, 102], [100, 102]])

    assert_equal [2.0], result.pluck(:gain)
  end
end
