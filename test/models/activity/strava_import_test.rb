require "test_helper"

class Activity::StravaImportTest < ActiveSupport::TestCase
  HEADER = "Activity ID,Activity Date,Activity Name,Activity Type,Elapsed Time,Distance,Elapsed Time,Moving Time,Distance,Timer Time"
  STARTED_AT = Time.utc(2026, 10, 23, 16, 22, 13)

  setup { @dir = Dir.mktmpdir }

  teardown { FileUtils.remove_entry(@dir) }

  test "imports runs from the fixture archive" do
    report = Activity.import_strava(file_fixture("strava").to_s)

    assert_equal 3, report.count(:imported)
    assert_equal 1, report.count(:non_run)
    assert_equal 1, report.count(:too_short)

    run = Activity.find_by!(source: "strava", external_id: "9001")
    assert_equal Time.utc(2026, 10, 23, 16, 22, 13), run.started_at
    assert_equal Time.utc(2026, 10, 23, 18, 22, 13), run.local_started_at
    assert_equal %(Evening, "fast" run), run.name
    assert_equal "running", run.activity_type
    assert_not run.indoor
    assert_in_delta 10050.5, run.distance_m
    assert_in_delta 3050.0, run.timer_s
    assert_in_delta 3000.0, run.moving_s
    assert_in_delta 3100.0, run.elapsed_s
    assert_in_delta 120.5, run.elevation_gain_m
    assert_in_delta 118.0, run.elevation_loss_m
    assert_equal 152, run.avg_hr
    assert_equal 178, run.max_hr
    assert_equal 640, run.calories
    assert_equal "Felt good,\nlegs ok", run.summary["Activity Description"]
    assert_equal "10.05", run.summary["Distance"]
    assert_equal "10050.5", run.summary["Distance 2"]
    assert_equal "3100", run.summary["Elapsed Time"]
    assert_equal "3100.0", run.summary["Elapsed Time 2"]
    assert_equal "activities/9001.fit.gz", run.summary["Filename"]
  end

  test "maps activity types" do
    Activity.import_strava(file_fixture("strava").to_s)

    assert_equal ["trail_running", false], Activity.find_by!(external_id: "9002").then { [it.activity_type, it.indoor] }
    assert_equal ["virtual_run", true], Activity.find_by!(external_id: "9003").then { [it.activity_type, it.indoor] }
  end

  test "blank fields become nil" do
    Activity.import_strava(file_fixture("strava").to_s)

    run = Activity.find_by!(external_id: "9003")
    assert_nil run.elevation_gain_m
    assert_nil run.elevation_loss_m
    assert_nil run.avg_hr
    assert_nil run.max_hr
    assert_nil run.calories
    assert_nil run.summary["Filename"]
  end

  test "timer time falls back to moving time then elapsed time" do
    import(
      strava_row(id: "1", timer: "2900", moving: "3000", elapsed: "3100"),
      strava_row(id: "2", date: "Oct 24, 2026, 4:22:13 PM", timer: "", moving: "3000", elapsed: "3100"),
      strava_row(id: "3", date: "Oct 25, 2026, 4:22:13 PM", timer: "", moving: "", elapsed: "3100")
    )

    assert_equal [2900.0, 3000.0, 3100.0], Activity.order(:external_id).pluck(:timer_s)
  end

  test "timer time falls back when the column is missing" do
    File.write(File.join(@dir, "activities.csv"), "Activity ID,Activity Date,Activity Name,Activity Type,Elapsed Time,Distance,Elapsed Time,Moving Time,Distance\n1,\"Oct 23, 2026, 4:22:13 PM\",Run,Run,3100,10.0,3100.0,3000.0,10000.0\n")

    report = Activity.import_strava(@dir)

    assert_equal 1, report.count(:imported)
    assert_in_delta 3000.0, Activity.last.timer_s
  end

  test "local time is Ljubljana wall-clock time on both sides of a DST change" do
    import(
      strava_row(id: "winter", date: "Mar 28, 2026, 12:00:00 PM"),
      strava_row(id: "summer", date: "Mar 29, 2026, 12:00:00 PM"),
      strava_row(id: "summer-end", date: "Oct 24, 2026, 12:00:00 PM"),
      strava_row(id: "winter-start", date: "Oct 26, 2026, 12:00:00 PM")
    )

    local_hours = Activity.order(:started_at).map { [it.started_at.hour, it.local_started_at.hour] }
    assert_equal [[12, 13], [12, 14], [12, 14], [12, 13]], local_hours
    assert_equal Time.utc(2026, 3, 29, 14), Activity.find_by!(external_id: "summer").local_started_at
  end

  test "midnight UTC rolls the local date forward" do
    import(strava_row(id: "1", date: "Oct 23, 2026, 11:30:00 PM"))

    assert_equal Time.utc(2026, 10, 24, 1, 30), Activity.last.local_started_at
  end

  test "skips runs under 100 m" do
    report = import(strava_row(id: "1", distance: "99.9"), strava_row(id: "2", date: "Oct 24, 2026, 4:22:13 PM", distance: "100"))

    assert_equal 1, report.count(:too_short)
    assert_equal ["2"], Activity.pluck(:external_id)
  end

  test "ignores non-run rows" do
    report = import(strava_row(id: "1", type: "Ride"), strava_row(id: "2", date: "Oct 24, 2026, 4:22:13 PM", type: "Walk"))

    assert_equal 2, report.count(:non_run)
    assert_equal 0, Activity.count
  end

  test "counts rows with unparseable dates or no durations as invalid" do
    report = import(strava_row(id: "1", date: "yesterday"), strava_row(id: "2", moving: "", elapsed: "", timer: ""))

    assert_equal 2, report.count(:invalid)
    assert_equal 0, Activity.count
  end

  test "counts rows with a blank or unparseable raw distance as invalid, not too short" do
    report = import(strava_row(id: "1", distance: ""), strava_row(id: "2", date: "Oct 24, 2026, 4:22:13 PM", distance: "n/a"))

    assert_equal 2, report.count(:invalid)
    assert_equal 0, report.count(:too_short)
    assert_equal 0, Activity.count
  end

  test "re-running is idempotent" do
    first = import(strava_row(id: "1"))
    second = import(strava_row(id: "1"))

    assert_equal 1, first.count(:imported)
    assert_equal 0, second.count(:imported)
    assert_equal 1, second.count(:already_imported)
    assert_equal 1, Activity.count
  end

  test "imports only runs that start more than 10 minutes before the first Garmin run" do
    create(:activity, started_at: STARTED_AT + 10.minutes)
    create(:activity, started_at: STARTED_AT + 1.year)

    report = import(
      strava_row(id: "before", date: "Oct 23, 2026, 4:22:12 PM"),
      strava_row(id: "margin", date: "Oct 23, 2026, 4:22:13 PM"),
      strava_row(id: "later", date: "Oct 24, 2026, 4:22:13 PM")
    )

    assert_equal ["before"], Activity.where(source: "strava").pluck(:external_id)
    assert_equal 2, report.count(:garmin_era)
    assert_includes report.to_s, "In Garmin's history: 2"
  end

  test "only Garmin runs start Garmin's history" do
    create(:activity, source: "strava", external_id: "other", started_at: STARTED_AT - 1.year)

    report = import(strava_row(id: "1"))

    assert_equal 1, report.count(:imported)
  end

  private
  def strava_row(id:, date: "Oct 23, 2026, 4:22:13 PM", name: "Run", type: "Run", distance: "10000.0", timer: "", moving: "3000.0", elapsed: "3100.0")
    %(#{id},"#{date}",#{name},#{type},#{elapsed},#{distance.to_f / 1000},#{elapsed},#{moving},#{distance},#{timer}\n)
  end

  def import(*rows)
    File.write(File.join(@dir, "activities.csv"), HEADER + "\n" + rows.join)
    Activity.import_strava(@dir)
  end
end
