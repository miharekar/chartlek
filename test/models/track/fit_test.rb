require "test_helper"

class Track::FitTest < ActiveSupport::TestCase
  setup { @rows = Track::Fit.parse(file_fixture("tracks/run.fit").to_s).rows }

  test "reads every record in the shared shape" do
    assert_equal 40, @rows.size
    assert_in_delta 46.0, @rows.first[:lat], 0.001
    assert_in_delta 14.0, @rows.first[:lng], 0.001
    assert_equal 300.0, @rows.first[:alt]
    assert_equal 140, @rows.first[:hr]
    assert_in_delta 1560.0, @rows.last[:d], 0.1
  end

  test "doubles cadence to both legs" do
    assert_equal 161.0, @rows.first[:cad]
  end

  test "removes the pause from timer time" do
    assert_equal 190.0, @rows[19][:t]
    assert_equal 200.0, @rows[20][:t]
    assert_equal 390.0, @rows.last[:t]
    assert_equal 490.0, @rows.last[:at] - @rows.first[:at]
  end

  test "reads a file whose lap message index is out of sequence" do
    activity = Fit4Ruby::Activity.new
    start = Time.utc(2024, 3, 5, 6, 30)
    3.times { activity.new_record(timestamp: start + it * 10, distance: it * 40.0, speed: 4.0, activity_type: "running") }
    activity.new_lap(timestamp: start + 20, sport: "running", message_index: 3)
    activity.new_session(timestamp: start + 20, sport: "running")

    Tempfile.create("odd.fit") do |file|
      Fit4Ruby.write(file.path, activity)

      assert_equal 3, Track::Fit.parse(file.path).size
    end
  end

  test "reads lap starts and intensities" do
    activity = Fit4Ruby::Activity.new
    start = Time.utc(2024, 3, 5, 6, 30)
    6.times { activity.new_record(timestamp: start + it * 10, distance: it * 40.0, speed: 4.0, activity_type: "running") }
    activity.new_lap(timestamp: start + 20, start_time: start, sport: "running", intensity: "warmup", message_index: 0)
    activity.new_lap(timestamp: start + 50, start_time: start + 20, sport: "running", intensity: "cooldown", message_index: 1)
    activity.new_session(timestamp: start + 50, sport: "running")

    Tempfile.create("laps.fit") do |file|
      Fit4Ruby.write(file.path, activity)

      assert_equal [[start.to_f, "warmup"], [start.to_f + 20, "cooldown"]], Track::Fit.parse(file.path).laps.map { [it[:at], it[:intensity]] }
    end
  end

  test "rejects a file that is not FIT" do
    Tempfile.create("bad.fit") do |file|
      file.write("not a fit file")
      file.flush

      assert_raises(Track::Error) { Track::Fit.parse(file.path) }
    end
  end
end
