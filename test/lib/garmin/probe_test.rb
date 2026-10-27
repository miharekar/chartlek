require "test_helper"
require_relative "api_stubs"

class Garmin::ProbeTest < ActiveSupport::TestCase
  include GarminApiStubs

  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "p5", "probe.txt")
    stub_token
    stub_request(:get, %r{#{BASE_URL}/}).to_return(status: 404)
    stub_request(:get, "#{BASE_URL}/userprofile-service/socialProfile").to_return(body: {displayName: "Jane Runner", fullName: "Jane Q. Runner"}.to_json)
    stub_request(:get, "#{BASE_URL}/userprofile-service/userprofile/settings").to_return(body: {userData: {gender: "FEMALE", weight: 61234.5}}.to_json)
    stub_request(:get, "#{BASE_URL}/hrv-service/hrv/#{Date.current - 1}").to_return(body: {hrvSummary: {lastNightAvg: 48712, status: "BALANCED"}, readings: [{hrvValue: 51234}], "2026-01-02": 1, "2026-10-27T06:00:00.0": 2, "2024": 3}.to_json)
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "prints keys and statuses, never values" do
    output, = capture_io { probe(scope: :all).run }

    assert_includes output, "GET /hrv-service/hrv/{date} [yesterday] -> 200"
    assert_includes output, "hrvSummary:object{lastNightAvg:number, status:string}"
    assert_includes output, "readings:array[1]{hrvValue:number}"
    assert_includes output, "<date>:number"
    assert_includes output, "<id>:number"
    assert_includes output, "GET /sleep-service/sleep/dailySleepData?date={date} [yesterday] -> 404"
    assert_includes output, "hrv: GET /hrv-service/hrv/{date}"
    assert_includes output, "sleep: not available"
    %w[Jane Runner 48712 51234 61234 BALANCED FEMALE 2026-01-02 06:00:00 2024].each { assert_not_includes output, it }
    assert_equal output, File.read(@path)
  end

  test "writes the output file at mode 600 in a 700 directory and stays within the budget" do
    client = Garmin::Client.new(key: "test-key")
    capture_io { probe(client, scope: :all).run }

    assert_equal 0o600, File.stat(@path).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(@path)).mode & 0o777
    assert_operator client.request_count, :<=, 70
  end

  test "documented endpoints print keys, counts and dates, never values, and stay within 30 requests" do
    stub_request(:get, "#{BASE_URL}/sleep-service/sleep/dailySleep").with(query: hash_including("date" => (Date.current - 1).to_s)).to_return(body: {dailySleepDTO: {sleepTimeSeconds: 27345, deepSleepSeconds: 5432, sleepScores: {overall: {value: 83, qualifierKey: "GOOD"}}, avgOvernightHrv: 61.5}, remSleepData: true, sleepMovement: [{startGMT: "2025-03-03T22:00:00.0", activityLevel: 0.5}]}.to_json)
    stub_request(:get, "#{BASE_URL}/usersummary-service/v2/dailysummaries").with(query: hash_including("endDate" => (Date.current - 1).to_s)).to_return(body: {data: [{calendarDate: "2025-03-04", heartRate: {restingValue: 49871}, respiration: {avgValue: 14.25}}]}.to_json)
    stub_request(:get, "#{BASE_URL}/activity-service/activity/9100001").to_return(body: {activityName: "Secret Loop", summaryDTO: {recoveryHeartRate: 31337, startLatitude: 12.3456}, splitSummaries: [{splitType: "INTERVAL_ACTIVE", maxHR: 171717}]}.to_json)
    create(:activity, source: "garmin")
    client = Garmin::Client.new(key: "test-key")

    output, = capture_io { probe(client, activity_id: 9100001).run }

    assert_includes output, "GET /sleep-service/sleep/dailySleep?date={date} [yesterday] -> 200"
    assert_includes output, "dailySleepDTO:object{sleepTimeSeconds:number, deepSleepSeconds:number, sleepScores:object{overall:object{value:number, qualifierKey:string}}, avgOvernightHrv:number}"
    assert_includes output, "GET /activity-service/activity/{activityId} [once] -> 200"
    assert_includes output, "summaryDTO:object{recoveryHeartRate:number, startLatitude:number}"
    assert_includes output, "splitSummaries:array[1]{splitType:string, maxHR:number}"
    assert_includes output, "sleep: GET /sleep-service/sleep/dailySleep?date={date}"
    %w[27345 5432 83 GOOD 61.5 Secret 31337 12.3456 171717 49871 14.25 2025-03-04 2025-03-03 22:00:00 9100001].each { assert_not_includes output, it }
    assert_operator client.request_count, :<=, 30
  end

  test "compares v2 with the stored days by count and never prints a value" do
    first, second = Date.current - 2, Date.current - 1
    WellnessDay.create!(date: first, resting_hr: 4141, stress_avg: 3131, body_battery_high: 9191, body_battery_low: 2121)
    WellnessDay.create!(date: second, resting_hr: 4242, stress_avg: 3232, body_battery_high: 9292, body_battery_low: 2222)
    v2 = [[first, 4141, 3131, 9191, 2121], [second, 4343, 3232, 9292, 2222]].map do |date, rhr, stress, high, low|
      {calendarDate: date.to_s, heartRate: {restingValue: rhr}, stress: {avgLevel: stress}, bodyBattery: {maxValue: high, minValue: low}}
    end
    stub_request(:get, "#{BASE_URL}/usersummary-service/v2/dailysummaries").with(query: {"startDate" => first.to_s, "endDate" => second.to_s}).to_return(body: {data: v2}.to_json)

    output, = capture_io { probe.run }

    assert_includes output, "resting_hr: 1 of 2 match"
    assert_includes output, "stress_avg: 2 of 2 match"
    assert_includes output, "body_battery_low: 2 of 2 match"
    %w[4141 4242 4343 3131 3232 9191 9292 2121 2222].each { assert_not_includes output, it }
  end

  private
  def probe(client = Garmin::Client.new(key: "test-key"), **options)
    Garmin::Probe.new(client:, first_run_on: Date.current - 3000, path: @path, **options)
  end
end
