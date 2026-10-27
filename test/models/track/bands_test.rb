require "test_helper"

class Track::BandsTest < ActiveSupport::TestCase
  ZONES = HrZones.new(floors: [100, 120, 140, 160, 180], max_hr: 200, source: "garmin")

  def data(speed:, seconds: 300, grade: 0.0, hr: nil)
    ts = (0..seconds).step(5).to_a
    {
      "t" => ts,
      "d" => ts.map { it * speed },
      "alt" => ts.map { 500.0 + it * speed * grade / 100 },
      "hr" => (ts.map { hr } if hr)
    }.compact
  end

  test "sums seconds in the pace zone of the speed" do
    pace = Track::Bands.new(data(speed: 3.0), ZONES).to_h["pace"]

    assert_equal 300, pace.sum
    assert_equal 300, pace[PaceZones.zone_for(10.8)]
  end

  test "stopped time lands in the walk zone" do
    pace = Track::Bands.new(data(speed: 0.0), ZONES).to_h["pace"]

    assert_equal 300, pace[0]
  end

  test "sums seconds per heart rate zone and clamps below the first floor" do
    assert_equal [0, 0, 300, 0, 0], Track::Bands.new(data(speed: 3.0, hr: 150), ZONES).to_h["hr"]
    assert_equal [300, 0, 0, 0, 0], Track::Bands.new(data(speed: 3.0, hr: 80), ZONES).to_h["hr"]
  end

  test "averages a window's heart rate without truncating" do
    window = {"t" => [0, 10, 20, 30], "d" => [0, 30, 60, 90]}

    assert_equal [0, 0, 30, 0, 0], Track::Bands.new(window.merge("hr" => [139, 141, 140, 140]), ZONES).to_h["hr"]
    assert_equal [0, 30, 0, 0, 0], Track::Bands.new(window.merge("hr" => [139, 140, 139, 140]), ZONES).to_h["hr"]
    assert_equal [0, 0, 30, 0, 0], Track::Bands.new(window.merge("hr" => [139, 140, 141, 140]), ZONES).to_h["hr"]
  end

  test "has no heart rate bands without heart rate or zones" do
    assert_nil Track::Bands.new(data(speed: 3.0), ZONES).to_h["hr"]
    assert_nil Track::Bands.new(data(speed: 3.0, hr: 150), nil).to_h["hr"]
  end

  test "buckets seconds by grade" do
    assert_equal 300, Track::Bands.new(data(speed: 3.0, grade: 0.0), ZONES).to_h["grade"][3]
    assert_equal 300, Track::Bands.new(data(speed: 3.0, grade: 2.0), ZONES).to_h["grade"][4]
    assert_equal 300, Track::Bands.new(data(speed: 3.0, grade: -10.0), ZONES).to_h["grade"][0]
    assert_equal 300, Track::Bands.new(data(speed: 3.0, grade: 9.0), ZONES).to_h["grade"][6]
  end

  test "has no grade bands without altitude or without distance" do
    assert_nil Track::Bands.new(data(speed: 3.0).except("alt"), ZONES).to_h["grade"]
    assert_nil Track::Bands.new(data(speed: 0.0), ZONES).to_h["grade"]
  end

  test "accepts symbol keys" do
    assert_equal 300, Track::Bands.new(data(speed: 3.0).symbolize_keys, ZONES).to_h["pace"].sum
  end
end
