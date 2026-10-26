require "test_helper"

class Activity::StravaLinkTest < ActiveSupport::TestCase
  RUN_AT = Time.utc(2026, 10, 20, 7, 0, 0)

  def garmin_run(at: RUN_AT)
    create(:activity, started_at: at, local_started_at: at)
  end

  def summary(id, at, sport_type: "Run")
    {"id" => id, "sport_type" => sport_type, "start_date" => at.iso8601}
  end

  def client(*summaries)
    Struct.new(:summaries) { def activities(after: nil) = summaries }.new(summaries)
  end

  test "links a Strava run to the nearest garmin run within ten minutes" do
    far = garmin_run(at: RUN_AT - 8.minutes)
    near = garmin_run(at: RUN_AT + 3.minutes)

    assert_equal 1, Activity.link_strava_now(full: true, client: client(summary(555, RUN_AT)))

    assert_equal 555, near.reload.strava_id
    assert_nil far.reload.strava_id
  end

  test "does not link outside the margin" do
    run = garmin_run(at: RUN_AT + 11.minutes)

    assert_equal 0, Activity.link_strava_now(full: true, client: client(summary(555, RUN_AT)))

    assert_nil run.reload.strava_id
  end

  test "links exactly ten minutes apart" do
    run = garmin_run(at: RUN_AT + 10.minutes)

    Activity.link_strava_now(full: true, client: client(summary(555, RUN_AT)))

    assert_equal 555, run.reload.strava_id
  end

  test "never overwrites an existing link and is idempotent" do
    linked = garmin_run
    linked.update!(strava_id: 111)

    assert_equal 0, Activity.link_strava_now(full: true, client: client(summary(555, RUN_AT)))
    assert_equal 0, Activity.link_strava_now(full: true, client: client(summary(111, RUN_AT)))

    assert_equal 111, linked.reload.strava_id
  end

  test "a second pass links nothing new" do
    run = garmin_run
    summaries = client(summary(555, RUN_AT))

    assert_equal 1, Activity.link_strava_now(full: true, client: summaries)
    assert_equal 0, Activity.link_strava_now(full: true, client: summaries)
    assert_equal 555, run.reload.strava_id
  end

  test "a Strava activity is linked to one run only" do
    first = garmin_run(at: RUN_AT)
    second = garmin_run(at: RUN_AT + 1.minute)

    assert_equal 1, Activity.link_strava_now(full: true, client: client(summary(555, RUN_AT)))

    assert_equal 555, first.reload.strava_id
    assert_nil second.reload.strava_id
  end

  test "ignores activities that are not runs" do
    run = garmin_run

    assert_equal 0, Activity.link_strava_now(full: true, client: client(summary(555, RUN_AT, sport_type: "Ride")))

    assert_nil run.reload.strava_id
  end

  test "strava sourced runs carry their own id" do
    run = create(:activity, source: "strava", external_id: "9001")

    assert_equal 9001, run.strava_id
    assert_equal "https://www.strava.com/activities/9001", run.strava_url
  end

  test "a garmin run keeps no strava id by default" do
    assert_nil garmin_run.strava_id
  end

  test "recent mode makes no request without unlinked recent runs" do
    old = garmin_run(at: 60.days.ago)
    spy = Class.new { attr_reader :called; def activities(after: nil) = (@called = true) && [] }.new

    assert_equal 0, Activity.link_strava_now(client: spy)

    assert_nil spy.called
    assert_nil old.reload.strava_id
  end

  test "recent mode asks only for activities after the oldest unlinked recent run" do
    run = garmin_run(at: 2.days.ago)
    after = nil
    recording = Class.new { define_method(:activities) { |after: nil| (@after = after) && [] }; attr_reader :after }.new

    Activity.link_strava_now(client: recording)

    assert_equal (run.started_at - 10.minutes).to_i, recording.after
  end

  test "sync later enqueues once for a full scan" do
    assert_enqueued_with(job: Activity::StravaLinkJob, args: [{full: true}]) { Activity.link_strava_later(full: true) }
  end

  test "the job does nothing when Strava is not connected" do
    garmin_run

    assert_nothing_raised { Activity::StravaLinkJob.perform_now(full: true) }
  end
end
