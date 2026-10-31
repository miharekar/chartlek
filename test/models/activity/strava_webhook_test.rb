require "test_helper"

class Activity::StravaWebhookTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  def handle(object_type:, aspect_type:, object_id: 1, updates: nil)
    Activity.handle_strava_event(object_type:, aspect_type:, object_id:, updates:)
  end

  def connect_strava
    Profile.instance.store_strava_tokens(access_token: "a-1", refresh_token: "r-1", expires_at: 6.hours.from_now.to_i)
  end

  test "an activity create queues a sync a minute out" do
    freeze_time do
      assert_enqueued_with(job: Activity::SyncJob, at: 1.minute.from_now) { handle(object_type: "activity", aspect_type: "create") }
    end
  end

  test "an activity delete unlinks a Garmin run and broadcasts a refresh" do
    run = create(:activity, strava_id: 42, strava_gear_id: "g1")
    other = create(:activity, strava_id: 43, strava_gear_id: "g2")

    streams = capture_broadcasts("garmin_sync") { handle(object_type: "activity", aspect_type: "delete", object_id: 42) }

    assert_nil run.reload.strava_id
    assert_nil run.strava_gear_id
    assert_equal 43, other.reload.strava_id
    assert_equal "g2", other.strava_gear_id
    assert_equal 1, streams.size
    assert_includes streams.first, "refresh"
  end

  test "an activity delete leaves a Strava-sourced run alone" do
    run = create(:activity, source: "strava", external_id: "42", strava_id: 42, strava_gear_id: "g1")

    streams = capture_broadcasts("garmin_sync") { handle(object_type: "activity", aspect_type: "delete", object_id: 42) }

    assert_equal 42, run.reload.strava_id
    assert_equal "g1", run.strava_gear_id
    assert_empty streams
  end

  test "an activity delete that matches nothing broadcasts nothing" do
    create(:activity, strava_id: 43)

    assert_no_broadcasts("garmin_sync") { handle(object_type: "activity", aspect_type: "delete", object_id: 42) }
    assert_no_broadcasts("garmin_sync") { handle(object_type: "activity", aspect_type: "delete", object_id: nil) }
  end

  test "an activity delete without a usable id never touches unlinked runs" do
    run = create(:activity, strava_id: nil, strava_gear_id: "g1")

    handle(object_type: "activity", aspect_type: "delete", object_id: nil)
    handle(object_type: "activity", aspect_type: "delete", object_id: "x")

    assert_equal "g1", run.reload.strava_gear_id
  end

  test "an athlete deauthorization disconnects Strava and broadcasts a refresh" do
    connect_strava

    streams = capture_broadcasts("garmin_sync") { handle(object_type: "athlete", aspect_type: "update", object_id: 9, updates: {"authorized" => "false"}) }

    assert_not Profile.instance.strava_connected?
    assert_equal 1, streams.size
  end

  test "other athlete updates, activity updates and unknown events change nothing" do
    connect_strava

    assert_no_broadcasts("garmin_sync") do
      handle(object_type: "athlete", aspect_type: "update", updates: {"authorized" => "true"})
      handle(object_type: "athlete", aspect_type: "update", updates: "false")
      handle(object_type: "athlete", aspect_type: "update", updates: nil)
      handle(object_type: "activity", aspect_type: "update", updates: {"title" => "New"})
      handle(object_type: "athlete", aspect_type: "create")
      handle(object_type: "bogus", aspect_type: "delete")
    end

    assert Profile.instance.strava_connected?
    assert_no_enqueued_jobs
  end
end
