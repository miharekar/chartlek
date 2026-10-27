require "test_helper"
require "rake"
require_relative "../lib/garmin/api_stubs"

class WellnessTaskTest < ActiveSupport::TestCase
  include GarminApiStubs

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("wellness:backfill")
    Rake::Task["wellness:backfill"].reenable
    stub_token
    stub_request(:get, /usersummary/).to_return(status: 200, body: {restingHeartRate: 50}.to_json)
    stub_request(:get, /hrv-service/).to_return(status: 204)
    stub_request(:get, /weight-service/).to_return(status: 200, body: {dailyWeightSummaries: []}.to_json)
    stub_request(:get, /heartRateZones/).to_return(status: 404)
  end

  teardown { ENV.delete("DAYS") }

  test "DAYS limits the backfill and the output has counts only" do
    create(:activity, local_started_at: Time.utc(2020, 1, 1, 7), max_hr: 180)
    ENV["DAYS"] = "5"

    output, = capture_io { Rake::Task["wellness:backfill"].invoke }

    assert_equal 5, WellnessDay.count
    assert_includes output, "summary: 5 days with data"
    assert_includes output, "HR zones from default"
  end
end
