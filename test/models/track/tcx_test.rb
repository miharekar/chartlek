require "test_helper"

class Track::TcxTest < ActiveSupport::TestCase
  setup { @rows = Track::Tcx.parse(file_fixture("tracks/run.tcx").read).rows }

  test "reads every trackpoint in the shared shape" do
    assert_equal 12, @rows.size
    assert_equal 46.0, @rows.first[:lat]
    assert_equal 14.0, @rows.first[:lng]
    assert_equal 200.5, @rows.first[:alt]
    assert_equal 150, @rows.first[:hr]
    assert_equal 400.0, @rows.last[:d]
  end

  test "keeps distance and heart rate of points without a position" do
    assert_nil @rows[8][:lat]
    assert_equal 280.0, @rows[8][:d]
    assert_equal 158, @rows[8][:hr]
  end

  test "doubles cadence to both legs" do
    assert_equal 170.0, @rows.first[:cad]
  end

  test "treats the gap before a new lap as a pause" do
    assert_equal 50.0, @rows[5][:t]
    assert_equal 50.0, @rows[6][:t]
    assert_equal 60.0, @rows[7][:t]
    assert_equal 100.0, @rows.last[:t]
  end

  def tcx(total, points)
    start = Time.utc(2017, 5, 7, 11)
    trackpoints = points.map { |seconds, d| "<Trackpoint><Time>#{(start + seconds).iso8601}</Time><DistanceMeters>#{d}</DistanceMeters></Trackpoint>" }
    total_time = "<TotalTimeSeconds>#{total}</TotalTimeSeconds>" if total

    "<TrainingCenterDatabase><Activities><Activity><Lap StartTime=\"#{start.iso8601}\">#{total_time}<Track>#{trackpoints.join}</Track></Lap></Activity></Activities></TrainingCenterDatabase>"
  end

  test "removes a stall inside a track, up to what the lap's total time leaves over" do
    rows = Track::Tcx.parse(tcx(70, [[0, 0], [10, 40], [20, 80], [30, 120], [130, 120], [140, 160], [150, 200]])).rows

    assert_equal [0.0, 10.0, 20.0, 30.0, 50.0, 60.0, 70.0], rows.pluck(:t)
  end

  test "keeps a gap where the distance keeps advancing" do
    rows = Track::Tcx.parse(tcx(140, [[0, 0], [60, 180], [120, 360], [180, 540]])).rows

    assert_equal 180.0, rows.last[:t]
  end

  test "keeps every gap when the lap has no total time" do
    rows = Track::Tcx.parse(tcx(nil, [[0, 0], [10, 40], [110, 40], [120, 80]])).rows

    assert_equal 120.0, rows.last[:t]
  end

  test "keeps a stall the lap's total time accounts for" do
    rows = Track::Tcx.parse(tcx(150, [[0, 0], [10, 40], [110, 40], [120, 80]])).rows

    assert_equal 120.0, rows.last[:t]
  end

  def tcx_laps(*laps)
    start = Time.utc(2017, 5, 7, 11)
    xml = laps.map do |offset, total, points|
      trackpoints = points.map { |seconds, d| "<Trackpoint><Time>#{(start + seconds).iso8601}</Time><DistanceMeters>#{d}</DistanceMeters></Trackpoint>" }
      "<Lap StartTime=\"#{(start + offset).iso8601}\"><TotalTimeSeconds>#{total}</TotalTimeSeconds><Track>#{trackpoints.join}</Track></Lap>"
    end

    "<TrainingCenterDatabase><Activities><Activity>#{xml.join}</Activity></Activities></TrainingCenterDatabase>"
  end

  test "measures a lap's excess from the time it adds, not from its start time" do
    rows = Track::Tcx.parse(tcx_laps([0, 100, [[3, 0], [13, 40], [23, 80], [33, 120], [133, 120], [143, 160]]])).rows

    assert_equal 100.0, rows.last[:t]
    assert_equal 30.0, rows[3][:t]
    assert_equal 90.0, rows[4][:t]
  end

  test "ignores a gap into a lap over the pause threshold when measuring its excess" do
    first = [0, 30, [[0, 0], [10, 40], [20, 80], [30, 120]]]
    second = [40, 90, [[55, 120], [65, 160], [75, 200], [175, 200], [185, 240]]]
    rows = Track::Tcx.parse(tcx_laps(first, second)).rows

    assert_equal 30.0, rows[3][:t]
    assert_equal 30.0, rows[4][:t]
    assert_equal 120.0, rows.last[:t]
  end

  test "counts a short gap into a lap when measuring its excess" do
    first = [0, 30, [[0, 0], [10, 40], [20, 80], [30, 120]]]
    second = [30, 100, [[35, 120], [45, 160], [55, 200], [155, 200], [165, 240]]]
    rows = Track::Tcx.parse(tcx_laps(first, second)).rows

    assert_equal 130.0, rows.last[:t]
  end
end
