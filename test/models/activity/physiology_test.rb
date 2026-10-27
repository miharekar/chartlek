require "test_helper"

class Activity::PhysiologyTest < ActiveSupport::TestCase
  ZONES = HrZones.new(floors: [100, 120, 140, 160, 180], max_hr: 200, source: "garmin")

  def summary(**extra)
    {"hrTimeInZone_1" => 60.0, "hrTimeInZone_2" => 180.0, "hrTimeInZone_3" => 360.0, "hrTimeInZone_4" => 0.0, "hrTimeInZone_5" => 0.0}.merge(extra.stringify_keys)
  end

  test "zone times carry minutes, share and the bpm range" do
    times = build(:activity, summary:).hr_zone_times(ZONES)

    assert_equal [1, 2, 3, 4, 5], times.pluck(:zone)
    assert_equal [60.0, 180.0, 360.0, 0.0, 0.0], times.pluck(:seconds)
    assert_equal [10, 30, 60, 0, 0], times.pluck(:percent)
    assert_equal [[100, 119], [120, 139], [140, 159], [160, 179], [180, 200]], times.map { [it[:from], it[:to]] }
  end

  test "zone times have no range without zones" do
    times = build(:activity, summary:).hr_zone_times(nil)

    assert_equal [nil] * 5, times.pluck(:from)
  end

  test "no zone times without a summary, without the fields or with all zero" do
    assert_nil build(:activity, summary: nil).hr_zone_times(ZONES)
    assert_nil build(:activity, summary: {"activityId" => 1}).hr_zone_times(ZONES)
    assert_nil build(:activity, summary: summary(hrTimeInZone_1: 0, hrTimeInZone_2: 0, hrTimeInZone_3: 0)).hr_zone_times(ZONES)
  end

  test "effort keeps only the fields the run has" do
    run = build(:activity, summary: summary(aerobicTrainingEffect: 3.2, trainingEffectLabel: "TEMPO", activityTrainingLoad: 120.4, differenceBodyBattery: -7, moderateIntensityMinutes: 12))

    assert_equal({aerobic: 3.2, label: "TEMPO", load: 120.4, body_battery: -7, moderate: 12}, run.effort)
    assert_equal({}, build(:activity, summary: nil).effort)
  end

  test "effort drops zero values but keeps a negative Body Battery change" do
    run = build(:activity, summary: summary(aerobicTrainingEffect: 0.0, anaerobicTrainingEffect: 0.0, activityTrainingLoad: 0.0, differenceBodyBattery: 0, moderateIntensityMinutes: 0, vigorousIntensityMinutes: 0))

    assert_equal({}, run.effort)
    assert_equal({body_battery: -3}, build(:activity, summary: summary(differenceBodyBattery: -3, moderateIntensityMinutes: 0)).effort)
  end

  test "running dynamics need recorded values" do
    run = build(:activity, summary: summary(avgGroundContactTime: 240.5, avgVerticalOscillation: 0, avgStrideLength: 105.2))

    assert_equal({ground_contact: 240.5, stride_length: 105.2}, run.running_dynamics)
  end

  test "going in is the wellness of the run's local day without its empty values" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 48, resting_hr_avg_7d: 50, hrv_last_night: nil, hrv_status: "BALANCED", body_battery_wake: 80, weight_kg: 70.5)
    WellnessDay.create!(date: Date.new(2024, 3, 4), resting_hr: 99)
    run = create(:activity, started_at: Time.utc(2024, 3, 4, 23, 30), local_started_at: Time.utc(2024, 3, 5, 0, 30))

    assert_equal({resting_hr: 48, resting_hr_avg_7d: 50, hrv_status: "BALANCED", body_battery_wake: 80}, run.going_in)
  end

  test "going in is nil without a wellness day and empty for an empty marker" do
    run = create(:activity)

    assert_nil run.going_in

    WellnessDay.create!(date: run.local_started_at.to_date, raw: {"summary" => {}})

    assert_equal({}, run.going_in)
  end

  test "going in is one query" do
    run = create(:activity)

    assert_queries_count(1) { run.going_in }
  end
end
