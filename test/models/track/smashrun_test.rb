require "test_helper"

class Track::SmashrunTest < ActiveSupport::TestCase
  setup { @rows = Track::Smashrun.parse(file_fixture("tracks/smashrun_pause.json").read).rows }

  test "reads the series-major recording in the shared shape" do
    assert_equal 26, @rows.size
    assert_in_delta 2400.0, @rows.last[:d], 0.01
    assert_equal 46.0, @rows.first[:lat]
    assert_equal 14.0, @rows.first[:lng]
    assert_equal 101.0, @rows[1][:alt]
    assert_equal 151, @rows[1][:hr]
  end

  test "doubles cadence to both legs" do
    assert_equal 170.0, @rows.first[:cad]
  end

  test "removes the pause at a pause index from timer time" do
    assert_equal 300.0, @rows[12][:t]
    assert_equal 300.0, @rows[13][:t]
    assert_equal 325.0, @rows[14][:t]
    assert_equal 600.0, @rows.last[:t]
  end

  test "takes timer time from a duration series" do
    body = {"recordingKeys" => %w[clock duration distance], "recordingValues" => [[0, 10, 120], [0, 10, 20], [0, 0.04, 0.07]]}
    rows = Track::Smashrun.parse(body.to_json).rows

    assert_equal [0.0, 10.0, 20.0], rows.pluck(:t)
    assert_equal [0.0, 40.0, 70.0], rows.pluck(:d)
  end

  test "rejects an activity whose details carry no recording" do
    error = assert_raises(Track::Error) { Track::Smashrun.parse({"activityId" => 1, "hasDetails" => 1, "recordingKeys" => nil, "recordingValues" => nil}.to_json) }

    assert_equal "Smashrun activity has no recording", error.message
  end

  test "rejects a recording without a clock" do
    assert_raises(Track::Error) { Track::Smashrun.parse({"recordingKeys" => ["distance"], "recordingValues" => [[0]]}.to_json) }
  end

  test "treats the -1/-1 marker as no position and keeps the rest of the sample" do
    body = {
      "recordingKeys" => %w[clock distance latitude longitude elevation heartRate],
      "recordingValues" => [[0, 10, 20, 30], [0, 0.01, 0.02, 0.03], [46.0, -1.0, -1.0, 46.002], [14.0, -1.0, -1.0, 14.002], [300.0, 301.0, 302.0, 303.0], [140, 141, 142, 143]]
    }
    rows = Track::Smashrun.parse(body.to_json).rows

    assert_equal [46.0, nil, nil, 46.002], rows.pluck(:lat)
    assert_equal [14.0, nil, nil, 14.002], rows.pluck(:lng)
    assert_equal [300.0, 301.0, 302.0, 303.0], rows.pluck(:alt)
    assert_equal [140, 141, 142, 143], rows.pluck(:hr)
  end

  test "keeps a real position on the equator or the prime meridian" do
    body = {"recordingKeys" => %w[clock latitude longitude], "recordingValues" => [[0, 10], [0.0, -1.0], [-1.0, 14.0]]}
    rows = Track::Smashrun.parse(body.to_json).rows

    assert_equal [0.0, -1.0], rows.pluck(:lat)
    assert_equal [-1.0, 14.0], rows.pluck(:lng)
  end
end
