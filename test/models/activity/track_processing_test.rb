require "test_helper"

class Activity::TrackProcessingTest < ActiveSupport::TestCase
  def zip(name, content)
    Zip::OutputStream.write_buffer { |zip| zip.put_next_entry(name) && zip.write(content) }.string
  end

  def attach(activity, filename, content, type)
    activity.original.attach(io: StringIO.new(content), filename:, content_type: type)
  end

  def garmin_run(**attributes)
    create(:activity, source: "garmin", started_at: Time.utc(2024, 3, 5, 6, 30), distance_m: 1560.0, timer_s: 390.0, elapsed_s: 490.0, **attributes)
  end

  test "processes a Garmin FIT zip end to end" do
    activity = garmin_run
    attach(activity, "#{activity.external_id}.zip", zip("1_ACTIVITY.fit", file_fixture("tracks/run.fit").binread), "application/zip")

    activity.process_original
    activity.reload

    data = activity.track.data
    assert_equal %w[t d lat lng alt hr cad], data.keys
    assert_equal 40, data["t"].size
    assert_equal 390.0, data["t"].last
    assert_in_delta 1560.0, data["d"].last, 0.1
    assert_equal 161, data["cad"].first
    assert_equal [1000.0, 560.0], activity.splits.pluck("distance")
    assert_equal 20, activity.pace_profile.size
    assert_not_nil activity.pace_variability
    assert_not activity.track.chart_metrics.key?("speed_windows")
    assert_equal 16, activity.track.chart_metrics["elevation"].size
  end

  test "clips a Garmin recording to the summary timer" do
    activity = garmin_run(distance_m: 760.0, timer_s: 190.0)
    attach(activity, "#{activity.external_id}.zip", zip("1_ACTIVITY.fit", file_fixture("tracks/run.fit").binread), "application/zip")

    activity.process_original

    assert_equal 20, activity.track.data["t"].size
    assert_in_delta 760.0, activity.track.data["d"].last, 0.1
  end

  test "processes a Garmin TCX zip" do
    activity = garmin_run(started_at: Time.utc(2017, 5, 7, 11), distance_m: 400.0, timer_s: 100.0, elapsed_s: 210.0)
    attach(activity, "#{activity.external_id}.zip", zip("1_UNKNOWN.tcx", file_fixture("tracks/run.tcx").read), "application/zip")

    activity.process_original

    assert_equal 12, activity.track.data["t"].size
    assert_equal 100.0, activity.track.data["t"].last
    assert_equal [400.0], activity.splits.pluck("distance")
  end

  test "processes a Smashrun gzip without clipping" do
    activity = create(:activity, source: "strava", distance_m: 2400.0, timer_s: 600.0)
    attach(activity, "smashrun-1001.json.gz", Zlib.gzip(file_fixture("tracks/smashrun_pause.json").read), "application/gzip")

    activity.process_original
    activity.reload

    assert_equal 26, activity.track.data["t"].size
    assert_equal 600.0, activity.track.data["t"].last
    assert_equal 170, activity.track.data["cad"].first
    assert_equal [250.0, 250.0, 250.0], activity.splits.pluck("pace")
    assert_equal 0.0, activity.pace_variability
  end

  test "rebuilds a broken Smashrun distance series" do
    activity = create(:activity, source: "smashrun", distance_m: 5000.0, timer_s: 270.0)
    attach(activity, "smashrun-1002.json.gz", Zlib.gzip(file_fixture("tracks/smashrun_broken.json").read), "application/gzip")

    activity.process_original

    assert_equal 5000.0, activity.track.data["d"].last
    assert_equal 2777.8, activity.track.data["d"][5]
    assert_equal %w[t d hr], activity.track.data.keys
    assert_nil activity.splits
    assert_nil activity.pace_profile
    assert_nil activity.pace_variability
    assert_nil activity.track.chart_metrics
  end

  test "processing again replaces the track" do
    activity = create(:activity, source: "smashrun", distance_m: 5000.0, timer_s: 270.0)
    attach(activity, "smashrun-1002.json.gz", Zlib.gzip(file_fixture("tracks/smashrun_broken.json").read), "application/gzip")

    2.times { activity.process_original }

    assert_equal 1, Track.where(activity:).count
  end

  test "chart metrics use the original samples before track downsampling" do
    activity = create(:activity, source: "strava", distance_m: 4000.0, timer_s: 4000.0)
    body = {"recordingKeys" => %w[clock distance elevation], "recordingValues" => [(0..4000).to_a, (0..4000).map { it / 1000.0 }, (0..4000).map { it.odd? ? 105.0 : 100.0 }]}.to_json
    attach(activity, "smashrun-1004.json.gz", Zlib.gzip(body), "application/gzip")
    activity.process_original

    assert_equal 2000, activity.track.data["t"].size
    metrics = activity.track.chart_metrics
    assert_equal 40, metrics["elevation"].size
    assert_equal 10_000, metrics["elevation"].sum { it["gain"] }
    assert_equal 10_000, metrics["elevation"].sum { it["loss"] }
    assert_equal 0, activity.pace_variability
  end

  test "rejects an unsupported file inside the zip" do
    activity = garmin_run
    attach(activity, "1.zip", zip("1.gpx", "<gpx/>"), "application/zip")

    error = assert_raises(Track::Error) { activity.process_original }
    assert_match "1.gpx", error.message
  end

  test "rejects an unsupported original" do
    activity = garmin_run
    attach(activity, "1.bin", "x", "application/octet-stream")

    assert_raises(Track::Error) { activity.process_original }
  end

  test "destroying the activity removes its track and original" do
    activity = create(:activity, source: "smashrun", distance_m: 5000.0, timer_s: 270.0)
    attach(activity, "smashrun-1002.json.gz", Zlib.gzip(file_fixture("tracks/smashrun_broken.json").read), "application/gzip")
    activity.process_original

    assert_difference -> { Track.count } => -1, -> { ActiveStorage::Blob.count } => -1 do
      activity.destroy
    end
  end

  def stopped_body
    {
      "recordingKeys" => %w[clock distance],
      "recordingValues" => [(0..11).map { it * 10 }, [0, 0.04, 0.08, 0.08, 0.08, 0.08, 0.12, 0.16, 0.2, 0.24, 0.28, 0.32]]
    }.to_json
  end

  test "a Smashrun recording leaves out stopped time beyond the run's timer" do
    activity = create(:activity, source: "strava", distance_m: 320.0, timer_s: 80.0)
    attach(activity, "smashrun-1003.json.gz", Zlib.gzip(stopped_body), "application/gzip")

    activity.process_original

    assert_equal 80.0, activity.track.data["t"].last
    assert_equal 320.0, activity.track.data["d"].last
  end

  test "a Smashrun recording shorter than the timer keeps its time" do
    activity = create(:activity, source: "strava", distance_m: 320.0, timer_s: 200.0)
    attach(activity, "smashrun-1003.json.gz", Zlib.gzip(stopped_body), "application/gzip")

    activity.process_original

    assert_equal 110.0, activity.track.data["t"].last
  end
end
