require "test_helper"
require_relative "../../lib/garmin/api_stubs"

class Wellness::SyncTest < ActiveSupport::TestCase
  include GarminApiStubs

  SUMMARY_URL = "#{BASE_URL}/usersummary-service/usersummary/daily"
  HRV_URL = %r{#{BASE_URL}/hrv-service/hrv/daily/}
  WEIGHT_URL = %r{#{BASE_URL}/weight-service/weight/range/}
  ZONES_URL = "#{BASE_URL}/biometric-service/heartRateZones/v2"

  setup do
    stub_token
    @today = Date.new(2026, 10, 27)
    @sync = Wellness::Sync.new(client: Garmin::Client.new(key: "test-key"))
  end

  def summary(**overrides)
    {restingHeartRate: 50, lastSevenDaysAvgRestingHeartRate: 51, averageStressLevel: 30, bodyBatteryHighestValue: 90, bodyBatteryLowestValue: 10, bodyBatteryAtWakeTime: 80}.merge(overrides)
  end

  def stub_summary(date, body, status: 200)
    stub_request(:get, SUMMARY_URL).with(query: {calendarDate: date.to_s}).to_return(status:, body: body&.to_json.to_s)
  end

  def stub_summaries(**overrides)
    stub_request(:get, SUMMARY_URL).with(query: hash_including("calendarDate")).to_return { {status: 200, body: summary(**overrides).to_json} }
  end

  def stub_hrv(summaries)
    stub_request(:get, HRV_URL).to_return(status: 200, body: {hrvSummaries: summaries}.to_json)
  end

  def stub_weight(summaries)
    stub_request(:get, WEIGHT_URL).with(query: {includeAll: "true"}).to_return(status: 200, body: {dailyWeightSummaries: summaries}.to_json)
  end

  def stub_zones(body = [], status: 200)
    stub_request(:get, ZONES_URL).to_return(status:, body: body.to_json)
  end

  def hrv_day(date, **overrides)
    {calendarDate: date.to_s, lastNightAvg: 60, weeklyAvg: 58, status: "BALANCED", baseline: {balancedLow: 50, balancedUpper: 70}}.merge(overrides)
  end

  test "refresh stores every metric for the day" do
    stub_summary(@today, summary)
    stub_summary(@today - 1, nil, status: 204)
    stub_summary(@today - 2, summary(restingHeartRate: nil, lastSevenDaysAvgRestingHeartRate: nil, averageStressLevel: nil, bodyBatteryHighestValue: nil, bodyBatteryLowestValue: nil, bodyBatteryAtWakeTime: nil))
    stub_summary(@today - 3, summary(restingHeartRate: 52))
    stub_hrv([hrv_day(@today)])
    stub_weight([{summaryDate: @today.to_s, latestWeight: {weight: 70_250.0}}])
    stub_zones

    @sync.refresh(today: @today)

    day = WellnessDay.find_by!(date: @today)
    assert_equal [50, 51, 30, 90, 10, 80], [day.resting_hr, day.resting_hr_avg_7d, day.stress_avg, day.body_battery_high, day.body_battery_low, day.body_battery_wake]
    assert_equal [60, 58, 50, 70, "BALANCED", 70.25], [day.hrv_last_night, day.hrv_weekly_avg, day.hrv_baseline_low, day.hrv_baseline_high, day.hrv_status, day.weight_kg]
    assert_equal [@today - 3, @today], WellnessDay.where.not(resting_hr: nil).order(:date).pluck(:date)
    assert_equal 52, WellnessDay.find_by!(date: @today - 3).resting_hr
    assert_equal %w[hrv summary weight], day.raw.keys.sort
    assert Profile.instance.wellness_synced_at
  end

  test "refresh is idempotent and updates late data in place" do
    stub_summaries
    stub_hrv([])
    stub_weight([])
    stub_zones

    2.times { @sync.refresh(today: @today) }
    assert_equal 4, WellnessDay.count

    stub_summaries(restingHeartRate: 47)
    @sync.refresh(today: @today)

    assert_equal 4, WellnessDay.count
    assert_equal [47], WellnessDay.distinct.pluck(:resting_hr)
  end

  test "refresh asks for today and the 3 days before it" do
    summaries = stub_summaries
    stub_hrv([])
    weight = stub_weight([])
    stub_zones

    @sync.refresh(today: @today)

    assert_requested summaries, times: 4
    assert_requested :get, "#{BASE_URL}/hrv-service/hrv/daily/2026-10-24/2026-10-27"
    assert_requested weight, times: 1
    assert_requested :get, "#{BASE_URL}/weight-service/weight/range/2026-10-24/2026-10-27?includeAll=true"
    assert_not_requested :get, "#{SUMMARY_URL}?calendarDate=2026-10-23"
  end

  test "missing metrics leave their columns empty and keep what exists" do
    stub_summary(@today, summary)
    (1..3).each { stub_summary(@today - it, nil, status: 204) }
    stub_request(:get, HRV_URL).to_return(status: 204)
    stub_request(:get, WEIGHT_URL).with(query: {includeAll: "true"}).to_return(status: 200, body: {dailyWeightSummaries: [{summaryDate: @today.to_s, latestWeight: {weight: nil}}]}.to_json)
    stub_zones

    @sync.refresh(today: @today)

    day = WellnessDay.find_by!(date: @today)
    assert_equal 50, day.resting_hr
    assert_nil day.hrv_last_night
    assert_nil day.weight_kg
    assert_equal ["summary"], day.raw.keys

    stub_summary(@today, nil, status: 204)
    @sync.refresh(today: @today)

    assert_equal 50, WellnessDay.find_by!(date: @today).resting_hr
  end

  test "a refresh with null fields keeps the stored values and payload" do
    stub_summary(@today, summary)
    stub_hrv([])
    stub_weight([])
    stub_zones
    (1..3).each { stub_summary(@today - it, nil, status: 204) }
    @sync.refresh(today: @today)

    stub_summary(@today, summary(restingHeartRate: nil, averageStressLevel: nil, bodyBatteryHighestValue: 95, userProfileId: 1))
    @sync.refresh(today: @today)

    day = WellnessDay.find_by!(date: @today)
    assert_equal [50, 30, 95], [day.resting_hr, day.stress_avg, day.body_battery_high]
    assert_equal 50, day.raw.dig("summary", "restingHeartRate")
    assert_equal 95, day.raw.dig("summary", "bodyBatteryHighestValue")

    stub_summary(@today, summary(restingHeartRate: nil, lastSevenDaysAvgRestingHeartRate: nil, averageStressLevel: nil, bodyBatteryHighestValue: nil, bodyBatteryLowestValue: nil, bodyBatteryAtWakeTime: nil, userProfileId: 1))
    @sync.refresh(today: @today)

    assert_equal 50, WellnessDay.find_by!(date: @today).raw.dig("summary", "restingHeartRate")
  end

  test "empty days are remembered by the backfill and fetched again by a refresh" do
    empty = stub_request(:get, SUMMARY_URL).with(query: hash_including("calendarDate")).to_return(status: 204)
    stub_hrv([])
    stub_weight([])
    stub_zones

    @sync.backfill(from: @today - 9, to: @today)
    assert_requested empty, times: 10
    assert_equal [nil], WellnessDay.distinct.pluck(:resting_hr)

    @sync.backfill(from: @today - 9, to: @today)
    assert_requested empty, times: 10

    @sync.refresh(today: @today)
    assert_requested empty, times: 14
  end

  test "resuming a backfill reaches unfetched days past many stored chunks" do
    chunks = Wellness::Sync::STOP_AFTER + 2
    stored = chunks * Wellness::Sync::CHUNK_DAYS
    (0...stored).each { WellnessDay.create!(date: @today - it, resting_hr: 50, raw: {"summary" => {"restingHeartRate" => 50}}) }
    summaries = stub_summaries
    stub_hrv([])
    stub_weight([])
    stub_zones

    report = @sync.backfill(from: @today - stored - 29, to: @today)

    assert_requested summaries, times: 30
    assert_equal stored + 30, report[:summary]
    assert_equal stored + 30, WellnessDay.count
  end

  test "stores Garmin's running zones on the profile" do
    stub_summaries
    stub_hrv([])
    stub_weight([])
    stub_zones([
      {sport: "DEFAULT", zone1Floor: 90, zone2Floor: 110, zone3Floor: 130, zone4Floor: 150, zone5Floor: 170, maxHeartRateUsed: 190},
      {sport: "RUNNING", zone1Floor: 100, zone2Floor: 120, zone3Floor: 140, zone4Floor: 160, zone5Floor: 180, maxHeartRateUsed: 200}
    ])

    @sync.refresh(today: @today)

    zones = HrZones.current
    assert_equal "garmin", zones.source
    assert_equal [100, 120, 140, 160, 180], zones.floors
    assert_equal 200, zones.max_hr
  end

  test "zones without a max HR are not stored" do
    stub_summaries
    stub_hrv([])
    stub_weight([])
    stub_zones([{sport: "RUNNING", zone1Floor: 100, zone2Floor: 120, zone3Floor: 140, zone4Floor: 160, zone5Floor: 180, maxHeartRateUsed: nil}])

    @sync.refresh(today: @today)

    assert_nil Profile.instance.hr_zones
  end

  test "a failing zones call keeps the fallback and the rest of the sync" do
    create(:activity, max_hr: 190)
    stub_summaries
    stub_hrv([])
    stub_weight([])
    stub_zones(status: 404)

    @sync.refresh(today: @today)

    assert_equal "default", HrZones.current.source
    assert_equal 4, WellnessDay.count
    assert Profile.instance.wellness_synced_at
  end

  test "backfill works newest first in 30-day chunks and resumes" do
    stub_summaries
    stub_hrv([hrv_day(@today)])
    stub_weight([])
    stub_zones

    report = @sync.backfill(from: @today - 44, to: @today)

    assert_equal({summary: 45, hrv: 2, weight: 0}, report)
    assert_requested :get, "#{BASE_URL}/hrv-service/hrv/daily/2026-09-28/2026-10-27"
    assert_requested :get, "#{BASE_URL}/hrv-service/hrv/daily/2026-09-13/2026-09-27"
    assert_equal 45, WellnessDay.count

    WebMock.reset_executed_requests!
    @sync.backfill(from: @today - 44, to: @today)

    assert_not_requested :get, /usersummary/
  end

  test "backfill stops a metric after consecutive empty chunks" do
    summaries = stub_request(:get, SUMMARY_URL).with(query: hash_including("calendarDate")).to_return(status: 200, body: {restingHeartRate: nil}.to_json)
    hrv = stub_request(:get, HRV_URL).to_return(status: 204)
    stub_weight([])
    stub_zones
    stub_request(:get, "#{SUMMARY_URL}?calendarDate=#{@today}").to_return(status: 200, body: summary.to_json)

    report = @sync.backfill(from: @today - 365 * 3, to: @today)

    assert_equal 1, report[:summary]
    assert_requested hrv, times: Wellness::Sync::STOP_AFTER
    assert_requested summaries, times: Wellness::Sync::CHUNK_DAYS * (Wellness::Sync::STOP_AFTER + 1)
  end
end
