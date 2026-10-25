require "test_helper"

class SyncsControllerTest < ActionDispatch::IntegrationTest
  test "create enqueues a sync and redirects back" do
    assert_enqueued_with(job: Activity::SyncJob) do
      post sync_path, headers: {"HTTP_REFERER" => "http://www.example.com/pace_trend"}
    end

    assert_redirected_to "/pace_trend"
  end

  test "opening a page syncs when never synced" do
    assert_enqueued_with(job: Activity::SyncJob) { get "/overview" }
  end

  test "opening a page syncs when the last attempt is old" do
    Profile.instance.update!(synced_at: 31.minutes.ago)

    assert_enqueued_with(job: Activity::SyncJob) { get "/overview" }
  end

  test "opening a page does not sync after a recent success" do
    Profile.instance.update!(synced_at: 5.minutes.ago)

    assert_no_enqueued_jobs { get "/overview" }
  end

  test "opening a page does not sync after a recent failed attempt" do
    Profile.instance.update!(synced_at: 2.days.ago, sync_error: Profile::INVALID_KEY_ERROR)

    assert_no_enqueued_jobs { get "/overview" }
  end

  test "opening a page does not sync while syncing" do
    Profile.instance.update!(sync_started_at: 1.minute.ago)

    assert_no_enqueued_jobs { get "/overview" }
  end

  test "non-HTML requests do not sync" do
    assert_no_enqueued_jobs { get "/overview", as: :json }
  end

  test "nav shows sync status" do
    Profile.instance.update!(synced_at: 12.minutes.ago)

    get "/overview"

    assert_select "nav", /Synced 12 minutes ago/
    assert_select "nav form[action='/sync'] button:not([disabled])", "Sync now"
  end

  test "nav shows never synced" do
    get "/overview"

    assert_select "nav", /Never synced/
  end

  test "nav shows syncing" do
    Profile.instance.update!(sync_started_at: 1.minute.ago)

    get "/overview"

    assert_select "nav #sync_status", /Syncing…/
  end

  test "banner explains key rotation when the key is invalid" do
    Profile.instance.update!(sync_error: Profile::INVALID_KEY_ERROR)

    get "/overview"

    assert_select "a[href='https://connect.garmin.com/app/settings/personalApiToken']"
    assert_select "code", "GARMIN_API_TOKEN"
  end

  test "no banner for other errors" do
    Profile.instance.update!(sync_error: "Sync failed: boom")

    get "/overview"

    assert_select "a[href='https://connect.garmin.com/app/settings/personalApiToken']", false
    assert_select "nav", /Sync failed/
  end
end
