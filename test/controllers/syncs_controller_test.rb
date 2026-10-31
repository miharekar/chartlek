require "test_helper"

class SyncsControllerTest < ActionDispatch::IntegrationTest
  test "create enqueues a sync and redirects back" do
    assert_enqueued_with(job: Activity::SyncJob) do
      post sync_path, headers: {"HTTP_REFERER" => "http://www.example.com/pace_trend"}
    end

    assert_redirected_to "/pace_trend"
  end

  test "a Turbo request gets the status replaced with Syncing and no redirect" do
    assert_enqueued_with(job: Activity::SyncJob) do
      post sync_path, as: :turbo_stream
    end

    assert_response :success
    assert_turbo_stream action: "replace", target: "sync_status" do
      assert_select "span", "Syncing…"
    end
    assert_nil Profile.instance.sync_started_at
  end

  test "a queued status hides an older sync failure until the job reports" do
    Profile.instance.update!(sync_error: "Sync failed: boom")

    post sync_path, as: :turbo_stream

    assert_turbo_stream action: "replace", target: "sync_status" do
      assert_select "span", "Syncing…"
      assert_select "span", text: "Sync failed", count: 0
    end
  end

  test "opening a page never starts a sync" do
    Profile.instance.update!(synced_at: 2.days.ago)

    assert_no_enqueued_jobs do
      get "/overview"
      get "/runs"
    end
  end

  test "the Garmin sync is scheduled in production every 3 hours by default" do
    task = recurring_tasks("GARMIN_SYNC_SCHEDULE" => nil).fetch("garmin_sync")

    assert_equal "Activity::SyncJob", task["class"]
    assert_equal "every 3 hours", task["schedule"]
  end

  test "GARMIN_SYNC_SCHEDULE overrides the Garmin sync schedule, and a blank value keeps the default" do
    assert_equal "every 2 hours", recurring_tasks("GARMIN_SYNC_SCHEDULE" => "every 2 hours").dig("garmin_sync", "schedule")
    assert_equal "every 3 hours", recurring_tasks("GARMIN_SYNC_SCHEDULE" => "").dig("garmin_sync", "schedule")
  end

  test "nav shows sync status" do
    Profile.instance.update!(synced_at: 12.minutes.ago)

    get "/overview"

    assert_select "nav", /Synced 12 minutes ago/
    assert_select "nav time[datetime][data-controller=relative-time]", "12 minutes"
    assert_select "body[data-controller=live-refresh]"
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

  private
  def recurring_tasks(env)
    previous = env.keys.index_with { ENV[it] }
    env.each { |key, value| ENV[key] = value }
    ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).fetch("production")
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
