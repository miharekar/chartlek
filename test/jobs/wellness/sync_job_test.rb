require "test_helper"
require_relative "../../lib/garmin/api_stubs"

class Wellness::SyncJobTest < ActiveJob::TestCase
  include GarminApiStubs

  test "refreshes wellness without touching the run sync" do
    stub_token
    stub_request(:get, /usersummary/).to_return(status: 200, body: {restingHeartRate: 50}.to_json)
    stub_request(:get, /hrv-service/).to_return(status: 204)
    stub_request(:get, /weight-service/).to_return(status: 200, body: {dailyWeightSummaries: []}.to_json)
    stub_request(:get, /heartRateZones/).to_return(status: 404)

    Wellness::SyncJob.perform_now

    assert_equal 4, WellnessDay.count
    assert Profile.instance.wellness_synced_at
    assert_nil Profile.instance.synced_at
    assert_equal 0, Activity.count
  end

  test "is scheduled hourly in production, apart from the run sync" do
    tasks = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "Wellness::SyncJob", tasks.dig("wellness_sync", "class")
    assert_equal "every hour at minute 30", tasks.dig("wellness_sync", "schedule")
    assert_equal "Activity::SyncJob", tasks.dig("garmin_sync", "class")
  end
end
