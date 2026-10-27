require "test_helper"

class PaceZonesTest < ActiveSupport::TestCase
  test "walk is below 5.5 km/h and zoom is 23 km/h and up" do
    assert_equal 0, PaceZones.zone_for(0)
    assert_equal 0, PaceZones.zone_for(5.49)
    assert_equal 1, PaceZones.zone_for(5.5)
    assert_equal 35, PaceZones.zone_for(22.99)
    assert_equal 36, PaceZones.zone_for(23.0)
    assert_equal 36, PaceZones.zone_for(40)
  end

  test "zones are 0.5 km/h wide" do
    assert_equal 1, PaceZones.zone_for(5.99)
    assert_equal 2, PaceZones.zone_for(6.0)
    assert_equal 13, PaceZones.zone_for(11.5)
    assert_equal 12, PaceZones.zone_for(11.49)
  end

  test "labels are the pace at the upper edge, seconds rounded down" do
    assert_equal "walk", PaceZones.label(0)
    assert_equal "10:00", PaceZones.label(1)
    assert_equal "9:13", PaceZones.label(2)
    assert_equal "2:36", PaceZones.label(35)
    assert_equal "zoom", PaceZones.label(36)
  end

  test "range runs from the 25th percentile to the best, padded by one zone" do
    vdots = (1..100).map { Vdot.for(5000, 2400 - it * 6) }
    low = PaceZones.zone_for_vdot(vdots.sort[24])
    high = PaceZones.zone_for_vdot(vdots.max)

    assert_equal (low - 1)..(high + 1), PaceZones.range(vdots, high)
  end

  test "range stays within the 37 zones" do
    assert_equal 0..1, PaceZones.range([Vdot.for(5000, 5000)], 0)
    assert_equal 35..36, PaceZones.range([Vdot.for(5000, 700)], 36)
  end

  test "range widens to include a run outside it" do
    vdots = [Vdot.for(5000, 1500), Vdot.for(5000, 1400)]
    zone = PaceZones.zone_for_vdot(Vdot.for(5000, 2400))

    assert_equal zone..(PaceZones.zone_for_vdot(vdots.max) + 1), PaceZones.range(vdots, zone)
    assert_equal (PaceZones.zone_for_vdot(vdots.min) - 1)..36, PaceZones.range(vdots, 36)
  end

  test "range for a single run is three zones around it" do
    zone = PaceZones.zone_for_vdot(Vdot.for(5000, 1500))

    assert_equal (zone - 1)..(zone + 1), PaceZones.range([Vdot.for(5000, 1500)], zone)
  end

  test "range without history is the run's zone, padded" do
    assert_equal 9..11, PaceZones.range([], 10)
  end
end
