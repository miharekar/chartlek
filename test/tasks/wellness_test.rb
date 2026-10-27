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
    stub_request(:get, /sleep-service/).to_return(status: 200, body: "[]")
    stub_request(:get, /heartRateZones/).to_return(status: 404)
  end

  teardown { %w[DAYS ONLY].each { ENV.delete(it) } }

  test "an unknown ONLY name aborts with the valid ones and fetches nothing" do
    create(:activity, local_started_at: Time.utc(2020, 1, 1, 7), max_hr: 180)
    ENV["ONLY"] = "sleep,slep"

    _, err = capture_io { assert_raises(SystemExit) { Rake::Task["wellness:backfill"].invoke } }

    assert_includes err, "Unknown ONLY metric slep; use summary, hrv, weight, sleep"
    assert_not_requested :get, /usersummary|sleep-service|hrv-service|weight-service/
  end

  test "ONLY limits the metrics" do
    create(:activity, local_started_at: Time.utc(2020, 1, 1, 7), max_hr: 180)
    ENV["DAYS"] = "3"
    ENV["ONLY"] = "sleep"

    output, = capture_io { Rake::Task["wellness:backfill"].invoke }

    assert_includes output, "sleep: 0 days with data"
    assert_not_includes output, "summary:"
    assert_not_requested :get, /usersummary/
  end

  test "DAYS limits the backfill and the output has counts only" do
    create(:activity, local_started_at: Time.utc(2020, 1, 1, 7), max_hr: 180)
    ENV["DAYS"] = "5"

    output, = capture_io { Rake::Task["wellness:backfill"].invoke }

    assert_equal 5, WellnessDay.count
    assert_includes output, "summary: 5 days with data"
    assert_includes output, "sleep: 0 days with data"
    assert_includes output, "HR zones from default"
  end
end
