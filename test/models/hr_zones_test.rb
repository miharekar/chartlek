require "test_helper"

class HrZonesTest < ActiveSupport::TestCase
  test "uses Garmin's boundaries from the profile" do
    Profile.instance.update!(hr_zones: {"floors" => [100, 120, 140, 160, 180], "max_hr" => 200})

    zones = HrZones.current

    assert_equal "garmin", zones.source
    assert_equal [nil, 1, 1, 2, 3, 4, 5, 5], [99, 100, 119, 120, 140, 160, 180, 220].map { zones.zone(it) }
    assert_nil zones.zone(nil)
    assert_equal 100..119, zones.range(1)
    assert_equal 160..179, zones.range(4)
    assert_equal 180..200, zones.range(5)
  end

  test "falls back to the default bands of the highest recorded max HR" do
    create(:activity, max_hr: 180)
    create(:activity, max_hr: 190)

    zones = HrZones.current

    assert_equal "default", zones.source
    assert_equal [95, 114, 133, 152, 171], zones.floors
    assert_equal 190, zones.max_hr
    assert_equal 3, zones.zone(140)
  end

  test "nil bpm has no zone" do
    assert_nil HrZones.new(floors: [100, 120, 140, 160, 180], max_hr: 200, source: "default").zone(nil)
  end

  test "is nil without stored zones or recorded heart rate" do
    assert_nil HrZones.current
  end
end
