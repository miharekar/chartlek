require "test_helper"

class TrackTest < ActiveSupport::TestCase
  def track(data)
    Track.new(data:)
  end

  test "bars per 100 m with a partial last bar" do
    bars = track("t" => [0, 30, 60, 90], "d" => [0, 100, 200, 250], "hr" => [140, 150, 160, 170], "cad" => [170, 172, 174, 176]).bars

    assert_equal [100.0, 100.0, 50.0], bars.pluck(:distance)
    assert_equal [30.0, 30.0, 30.0], bars.pluck(:time)
    assert_equal [300.0, 300.0, 600.0], bars.pluck(:pace)
    assert_equal [150, 160, 170], bars.pluck(:hr)
    assert_equal [172, 174, 176], bars.pluck(:cad)
  end

  test "bars leave heart rate and cadence nil when the series is missing" do
    bars = track("t" => [0, 30, 60], "d" => [0, 100, 200]).bars

    assert_equal [nil, nil], bars.pluck(:hr)
    assert_equal [nil, nil], bars.pluck(:cad)
  end

  test "bars take a size" do
    assert_equal [200.0], track("t" => [0, 60], "d" => [0, 200]).bars(200).pluck(:distance)
  end
end
