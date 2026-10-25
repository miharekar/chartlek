require "test_helper"

class Activity::StravaImport::ApiTest < ActiveSupport::TestCase
  test "imports runs from Strava API summaries" do
    report = Activity.import_strava_activities([strava_summary])

    assert_equal 1, report.count(:imported)
    run = Activity.find_by!(source: "strava", external_id: "9001")
    assert_equal Time.utc(2015, 3, 24, 8, 12), run.started_at
    assert_equal Time.utc(2015, 3, 24, 9, 12), run.local_started_at
    assert_equal "Test Morning Run", run.name
    assert_equal "running", run.activity_type
    assert_not run.indoor
    assert_not run.race
    assert_in_delta 10050.5, run.distance_m
    assert_in_delta 3000.0, run.timer_s
    assert_in_delta 3000.0, run.moving_s
    assert_in_delta 3100.0, run.elapsed_s
    assert_in_delta 120.5, run.elevation_gain_m
    assert_nil run.elevation_loss_m
    assert_equal 152, run.avg_hr
    assert_equal 178, run.max_hr
    assert_in_delta 169.0, run.avg_cadence
    assert_in_delta 10.0, run.start_lat
    assert_in_delta 20.0, run.start_lng
    assert_equal "test-9001.fit", run.summary["external_id"]
  end

  test "maps sport types, treadmill runs and races" do
    Activity.import_strava_activities([
      strava_summary(id: 1, sport_type: "TrailRun", type: "Run"),
      strava_summary(id: 2, sport_type: "VirtualRun", type: "VirtualRun", trainer: true),
      strava_summary(id: 3, trainer: true),
      strava_summary(id: 4, workout_type: 1)
    ])

    mapped = Activity.order(:external_id).map { [it.activity_type, it.indoor, it.race] }
    assert_equal [["trail_running", false, false], ["virtual_run", true, false], ["treadmill_running", true, false], ["running", false, true]], mapped
  end

  test "counts other sports as non-runs" do
    report = Activity.import_strava_activities([strava_summary(sport_type: "Ride", type: "Ride"), strava_summary(id: 2, sport_type: "Walk", type: "Walk")])

    assert_equal 2, report.count(:non_run)
    assert_equal 0, Activity.count
  end

  test "timer time falls back to elapsed time when moving time is zero or missing" do
    Activity.import_strava_activities([strava_summary(id: 1, moving_time: 0), strava_summary(id: 2, moving_time: nil)])

    assert_equal [3100.0, 3100.0], Activity.order(:external_id).pluck(:timer_s)
  end

  test "missing optional fields become nil" do
    Activity.import_strava_activities([strava_summary(start_latlng: [], average_cadence: nil, average_heartrate: nil, max_heartrate: nil, trainer: nil)])

    run = Activity.last
    assert_nil run.start_lat
    assert_nil run.avg_cadence
    assert_nil run.avg_hr
    assert_not run.indoor
  end

  test "imports only runs from before Garmin's history and is idempotent" do
    create(:activity, started_at: Time.utc(2015, 3, 25))

    first = Activity.import_strava_activities([strava_summary, strava_summary(id: 9002, start_date: "2015-03-26T08:12:00Z")])
    second = Activity.import_strava_activities([strava_summary])

    assert_equal [1, 1], [first.count(:imported), first.count(:garmin_era)]
    assert_equal 1, second.count(:already_imported)
    assert_equal ["9001"], Activity.where(source: "strava").pluck(:external_id)
  end

  private
  def strava_summary(**overrides)
    JSON.parse(file_fixture("strava/activity.json").read).merge(overrides.stringify_keys)
  end
end
