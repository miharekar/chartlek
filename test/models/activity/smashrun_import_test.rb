require "test_helper"

class Activity::SmashrunImportTest < ActiveSupport::TestCase
  BASE_URL = Smashrun::Client::BASE_URL
  GARMIN_START = Time.utc(2017, 1, 3, 12, 42)

  setup do
    @original_sleeper = Smashrun::Client.sleeper
    Smashrun::Client.sleeper = ->(_) { }
    @io = StringIO.new
    create(:activity, source: "garmin", started_at: GARMIN_START, local_started_at: GARMIN_START + 1.hour)
    stub_request(:post, Smashrun::Client::LOGIN_URL).to_return(body: file_fixture("smashrun/login.json").read)
  end

  teardown { Smashrun::Client.sleeper = @original_sleeper }

  def summary(id, local, **attributes)
    {"activityId" => id, "startDateTimeLocal" => local, "distance" => 5.0, "duration" => 1500, "isRace" => 0, "isTreadmill" => 0, "calories" => 300}.merge(attributes.stringify_keys)
  end

  def stub_list(*summaries)
    stub_request(:get, "#{BASE_URL}/my/activities").to_return(body: summaries.to_json)
  end

  def stub_detail(id, body = file_fixture("smashrun/activity.json").read)
    stub_request(:get, "#{BASE_URL}/my/activities/#{id}").to_return(body:)
  end

  def import
    Activity.import_smashrun(Smashrun::Client.new(email: "runner@example.com", password: "s3cret-pass"), io: @io)
  end

  test "keeps only runs more than 10 minutes before the first Garmin run" do
    stub_list(
      summary(1, "2017-01-03T13:31:00+01:00"),
      summary(2, "2017-01-03T13:32:00+01:00"),
      summary(3, "2017-01-03T14:00:00+01:00")
    )
    stub_detail(1)

    report = import

    assert_equal 1, report.count(:created)
    assert_equal 2, report.count(:garmin_era)
    assert_equal ["1"], Activity.where(source: "smashrun").pluck(:external_id)
  end

  test "matches the nearest activity within 10 minutes" do
    far = create(:activity, source: "strava", started_at: Time.utc(2015, 3, 5, 6, 4), local_started_at: Time.utc(2015, 3, 5, 7, 4), calories: nil)
    near = create(:activity, source: "strava", started_at: Time.utc(2015, 3, 5, 6, 12), local_started_at: Time.utc(2015, 3, 5, 7, 12), calories: nil)
    stub_list(summary(1000002, "2015-03-05T07:10:00+01:00"))
    stub_detail(1000002)

    report = import

    assert_equal 1, report.count(:matched)
    assert_equal 0, report.count(:created)
    assert_equal 300, near.reload.calories
    assert_nil far.reload.calories
    assert near.original.attached?
    assert_not far.original.attached?
  end

  test "sets race but never unsets it, and fills calories only when nil" do
    raced = create(:activity, source: "strava", started_at: Time.utc(2015, 3, 5, 6, 10), local_started_at: Time.utc(2015, 3, 5, 7, 10), calories: 500, race: false)
    kept = create(:activity, source: "strava", started_at: Time.utc(2015, 4, 5, 6, 10), local_started_at: Time.utc(2015, 4, 5, 7, 10), calories: nil, race: true)
    stub_list(summary(1, "2015-03-05T07:10:00+01:00", isRace: 1), summary(2, "2015-04-05T07:10:00+01:00", isRace: 0))
    stub_detail(1)
    stub_detail(2)

    import

    assert raced.reload.race
    assert_equal 500, raced.calories
    assert kept.reload.race
    assert_equal 300, kept.calories
  end

  test "creates a row from a summary" do
    stub_list(summary(1000001, "2015-03-03T15:31:00+01:00", isTreadmill: 1, isRace: 1, distance: 8.0, duration: 2400, heartRateAverage: 150, heartRateMax: 170, cadenceAverage: 80, cadenceMax: 90, elevationGain: 12.5, elevationLoss: 10.5, startLatitude: 10.5, startLongitude: 20.5))
    stub_detail(1000001)

    import

    run = Activity.find_by!(source: "smashrun", external_id: "1000001")
    assert_equal Time.utc(2015, 3, 3, 14, 31), run.started_at
    assert_equal Time.utc(2015, 3, 3, 15, 31), run.local_started_at
    assert_equal "treadmill_running", run.activity_type
    assert run.indoor
    assert run.race
    assert_in_delta 8000.0, run.distance_m
    assert_in_delta 2400.0, run.timer_s
    assert_equal [150, 170, 160.0, 180.0, 300], run.attributes.values_at("avg_hr", "max_hr", "avg_cadence", "max_cadence", "calories")
    assert_equal [12.5, 10.5, 10.5, 20.5], run.attributes.values_at("elevation_gain_m", "elevation_loss_m", "start_lat", "start_lng")
    assert_equal 1000001, run.summary["activityId"]
  end

  test "creates an outdoor run as running" do
    stub_list(summary(1, "2015-03-05T07:10:00+01:00"))
    stub_detail(1)

    import

    run = Activity.find_by!(source: "smashrun")
    assert_equal "running", run.activity_type
    assert_not run.indoor
    assert_not run.race
  end

  test "attaches the gzipped detail and processes it" do
    stub_list(summary(1000002, "2015-03-05T07:10:00+01:00", distance: 5.25, duration: 1500))
    stub_detail(1000002)

    report = import

    run = Activity.find_by!(source: "smashrun")
    assert_equal 1, report.count(:fetched)
    assert_equal "smashrun-1000002.json.gz", run.original.filename.to_s
    assert_equal "application/gzip", run.original.content_type
    assert_equal file_fixture("smashrun/activity.json").read, ActiveSupport::Gzip.decompress(run.original.download)
    assert run.track.present?
    assert_includes @io.string, "Fetching 1/1"
  end

  test "resuming skips rows that already have an original" do
    stub_list(summary(1000002, "2015-03-05T07:10:00+01:00", distance: 5.25, duration: 1500))
    detail = stub_detail(1000002)

    import
    report = import

    assert_requested detail, times: 1
    assert_equal 1, report.count(:matched)
    assert_equal 0, report.count(:fetched)
    assert_equal 1, Activity.where(source: "smashrun").count
  end

  test "counts failures without stopping" do
    stub_list(summary(1, "2015-03-05T07:10:00+01:00"), summary(2, "2015-03-06T07:10:00+01:00"), summary(3, "2015-03-07T07:10:00+01:00", distance: 5.25, duration: 1500))
    stub_detail(1, {recordingKeys: ["distance"], recordingValues: [[0]]}.to_json)
    stub_request(:get, "#{BASE_URL}/my/activities/2").to_return(status: 404)
    stub_detail(3)

    report = import

    broken = Activity.find_by!(external_id: "1")
    missing = Activity.find_by!(external_id: "2")
    assert_equal 2, report.count(:fetched)
    assert_equal [broken.id, missing.id], report.failures.map(&:first)
    assert broken.original.attached?
    assert_not missing.original.attached?
    assert Activity.find_by!(external_id: "3").track.present?
    assert_includes report.to_s, "Failed: 2"
  end

  test "continues after a non-Smashrun error" do
    stub_list(summary(1, "2015-03-05T07:10:00+01:00"), summary(2, "2015-03-06T07:10:00+01:00", distance: 5.25, duration: 1500))
    stub_request(:get, "#{BASE_URL}/my/activities/1").to_raise(Net::ReadTimeout)
    stub_detail(2)

    report = import

    assert_equal 1, report.failures.size
    assert_match(/\ANet::ReadTimeout: /, report.failures.first.last)
    assert Activity.find_by!(external_id: "2").track.present?
  end

  test "matches on the wall clock when the UTC start is an hour off" do
    existing = create(:activity, source: "strava", started_at: Time.utc(2016, 11, 15, 8, 30), local_started_at: Time.utc(2016, 11, 15, 8, 30), calories: nil)
    stub_list(summary(1, "2016-11-15T08:30:00+01:00"))
    stub_detail(1)

    report = import

    assert_equal 1, report.count(:matched)
    assert_equal 0, report.count(:created)
    assert_equal 300, existing.reload.calories
    assert_equal 0, Activity.where(source: "smashrun").count
  end
end
