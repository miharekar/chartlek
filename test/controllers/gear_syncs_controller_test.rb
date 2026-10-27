require "test_helper"

class GearSyncsControllerTest < ActionDispatch::IntegrationTest
  test "queues a full gear scan and redirects back with a notice" do
    profile = Profile.instance
    profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    profile.update!(strava_scope: "activity:read_all,profile:read_all")

    assert_enqueued_with(job: Activity::StravaGearJob, args: [{full: true}]) { post gear_sync_path }

    assert_redirected_to gears_path
    assert_match "Gear scan started", flash[:notice]
  end

  test "without gear access it queues nothing and says why" do
    assert_no_enqueued_jobs { post gear_sync_path }

    assert_redirected_to gears_path
    assert_match "Reconnect Strava", flash[:alert]
  end
end
