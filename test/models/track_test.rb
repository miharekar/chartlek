require "test_helper"

class TrackTest < ActiveSupport::TestCase
  def track(data)
    Track.new(data:)
  end

  test "wheel bars drop the partial last bar and keep each whole bar's own position" do
    bars = track("t" => [0, 30, 60, 90], "d" => [0, 100, 200, 250]).wheel_bars

    assert_equal [{from: 0.0, to: 0.1, distance: 100.0, time: 30.0}, {from: 0.1, to: 0.2, distance: 100.0, time: 30.0}], bars
  end

  test "wheel bars skip a zero-time bar without shifting the later ones" do
    bars = track("t" => [0, 30, 30, 60], "d" => [0, 100, 200, 300]).wheel_bars

    assert_equal [0.0, 0.2], bars.pluck(:from)
    assert_equal [0.1, 0.3], bars.pluck(:to)
    assert bars.all? { it[:time].positive? }
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

  test "route skips points without coordinates" do
    assert_equal [[2.0, 1.0], [6.0, 5.0]], track("lat" => [1.0, nil, 5.0], "lng" => [2.0, nil, 6.0]).route
    assert_equal [], track("t" => [0, 1]).route
  end

  test "route distances line up with the route and skip the same points" do
    located = track("d" => [0, 10, 20], "lat" => [1.0, nil, 5.0], "lng" => [2.0, nil, 6.0])

    assert_equal [0, 20], located.route_distances
    assert_equal located.route.size, located.route_distances.size
    assert_equal [], track("t" => [0, 1]).route_distances
  end

  test "each route point is paired with the distance of its own row" do
    rows = {"d" => [0, 10, 25, 40, 70], "lat" => [1.0, nil, 3.0, 4.0, nil], "lng" => [10.0, nil, 30.0, 40.0, nil]}
    located = track(rows)

    assert_equal [[10.0, 1.0], [30.0, 3.0], [40.0, 4.0]], located.route
    assert_equal [0, 25, 40], located.route_distances
    located.route.zip(located.route_distances).each do |(lng, lat), distance|
      row = rows["d"].index(distance)
      assert_equal [rows["lng"][row], rows["lat"][row]], [lng, lat]
    end
  end
end
