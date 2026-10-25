require "test_helper"
require_relative "../lib/garmin/api_stubs"

class Activity::SyncJobTest < ActiveJob::TestCase
  include GarminApiStubs

  test "runs a sync" do
    stub_token
    stub_settings
    stub_page(0, [garmin_summary])

    Activity::SyncJob.perform_now

    assert_equal 1, Activity.count
    assert Profile.instance.synced_at
  end
end
