require "test_helper"

class RunPhysiologyTest < ActionDispatch::IntegrationTest
  setup { Profile.instance.update!(hr_zones: {"floors" => [100, 120, 140, 160, 180], "max_hr" => 200}) }

  def summary(**extra)
    {"hrTimeInZone_1" => 60.0, "hrTimeInZone_2" => 180.0, "hrTimeInZone_3" => 360.0, "hrTimeInZone_4" => 0.0, "hrTimeInZone_5" => 0.0}.merge(extra.stringify_keys)
  end

  test "the zones card shows the bar, the ranges and the effort fields the run has" do
    run = create(:activity, avg_hr: 140, summary: summary(aerobicTrainingEffect: 3.2, trainingEffectLabel: "AEROBIC_BASE", activityTrainingLoad: 120.4, differenceBodyBattery: -7, moderateIntensityMinutes: 20, vigorousIntensityMinutes: 5))

    get run_path(run)

    assert_select "h2", text: "Heart rate zones and effort"
    assert_select "[data-controller=hr-zones] [data-hr-zones-target=segment]", 3
    assert_select "[data-controller=hr-zones][role=group][aria-label*='zone 3 6 min, 60 percent']"
    assert_select "[data-hr-zones-target=segment][tabindex='0']", 1
    assert_select "dt", text: /Zone 3/
    assert_select "dd", text: "6 min"
    assert_select "dd", text: "60%"
    assert_select "dd", text: "140–159"
    assert_select "h3", text: "Aerobic effect"
    assert_select "p", text: /3\.2/
    assert_select "p", text: "Aerobic base"
    assert_select "h3", text: "Training load"
    assert_select "h3", text: "Body Battery change"
    assert_select "p", text: /−7/
    assert_select "h3", text: "Intensity minutes"
    assert_select "p", text: "20 moderate · 5 vigorous"
    assert_select "h3", text: "Anaerobic effect", count: 0
    assert_select "dt", text: "Ground contact", count: 0
    assert_select "p", text: /default bands/, count: 0
  end

  test "running dynamics show only when recorded" do
    run = create(:activity, avg_hr: 140, summary: summary(avgGroundContactTime: 240.4, avgVerticalOscillation: 8.26, avgStrideLength: 105.2, avgVerticalRatio: 7.9))

    get run_path(run)

    assert_select "dt", text: "Ground contact"
    assert_select "dd", text: "240 ms"
    assert_select "dd", text: "8.3 cm"
    assert_select "dd", text: "1.05 m"
    assert_select "dd", text: "7.9%"
  end

  test "a run without zone times or HR has no zones card" do
    run = create(:activity, summary: {"activityId" => 1})

    get run_path(run)

    assert_response :success
    assert_select "h2", text: "Heart rate zones and effort", count: 0
    assert_select "[data-controller=hr-zones]", false
  end

  test "without Garmin's zones the card says the ranges are default bands" do
    Profile.instance.update!(hr_zones: nil)
    create(:activity, max_hr: 190)
    run = create(:activity, avg_hr: 140, summary:)

    get run_path(run)

    assert_select "p", text: /default bands/
    assert_select "dd", text: "133–151"
  end

  test "the HR chart gets the zone bands, and only when the track has HR" do
    run = create(:activity, avg_hr: 140, summary:)
    Track.create!(activity: run, data: {"t" => [0, 30], "d" => [0, 100], "hr" => [130, 150]})
    bare = create(:activity)
    Track.create!(activity: bare, data: {"t" => [0, 30], "d" => [0, 100], "alt" => [10, 12]})

    get run_path(run)

    assert_select "[data-controller=run-profiles][data-run-profiles-zones-value*='\"zone\":5,\"from\":180,\"to\":null']"

    get run_path(bare)

    assert_select "[data-controller=run-profiles][data-run-profiles-zones-value=?]", "[]"
  end

  test "going in shows the run's day without the missing values" do
    run = create(:activity)
    WellnessDay.create!(date: run.local_started_at.to_date, resting_hr: 48, resting_hr_avg_7d: 50, hrv_last_night: 62, hrv_status: "BALANCED", hrv_baseline_low: 55, hrv_baseline_high: 70, body_battery_wake: nil)

    get run_path(run)

    assert_select "h2", text: "Going in"
    assert_select "h3", text: "Resting HR"
    assert_select "p", text: "7-day average 50 bpm"
    assert_select "h3", text: "HRV last night"
    assert_select "p", text: "Balanced · baseline 55–70 ms"
    assert_select "h3", text: "Body Battery at wake", count: 0
    assert_select "h2", text: "Heart rate zones and effort", count: 0
    assert_select "section.lg\\:col-span-3 h2", text: "Going in"
  end

  test "going in shows last night's sleep with its score" do
    run = create(:activity)
    WellnessDay.create!(date: run.local_started_at.to_date, sleep_s: 27_900, sleep_score: 83)

    get run_path(run)

    assert_select "h2", text: "Going in"
    assert_select "h3", text: "Sleep last night"
    assert_select "p", text: /7:45/
    assert_select "p", text: "score 83"
  end

  test "going in is omitted for an empty day and shares the row with the zones card" do
    run = create(:activity, avg_hr: 140, summary:)
    WellnessDay.create!(date: run.local_started_at.to_date)

    get run_path(run)

    assert_select "h2", text: "Going in", count: 0
    assert_select "section.lg\\:col-span-3 h2", text: "Heart rate zones and effort"

    WellnessDay.find_by!(date: run.local_started_at.to_date).update!(body_battery_wake: 80)
    get run_path(run)

    assert_select "section.lg\\:col-span-2 h2", text: "Heart rate zones and effort"
    assert_select "section.lg\\:col-span-1 h2", text: "Going in"
    assert_select "p", text: /80/
  end

  test "zero effort values make no tiles, and the card says the ranges are today's zones" do
    run = create(:activity, avg_hr: 140, summary: summary(aerobicTrainingEffect: 0.0, anaerobicTrainingEffect: 0.0, activityTrainingLoad: 0.0, differenceBodyBattery: 0, moderateIntensityMinutes: 0, vigorousIntensityMinutes: 0))

    get run_path(run)

    assert_select "h2", text: /Heart rate zones and effort/
    ["Aerobic effect", "Anaerobic effect", "Training load", "Body Battery change", "Intensity minutes"].each { assert_select "h3", text: it, count: 0 }
    assert_select "p", text: /Estimated zones|default bands/, count: 0
    assert_select "h2 button[aria-label*='zones set on your watch']"
  end

  test "a run with stored zones shows its own ranges, and the estimated ones say so" do
    zones = {"floors" => [90, 110, 130, 150, 170], "max_hr" => 190, "seconds" => [60, 180, 360, 0, 0]}
    run = create(:activity, avg_hr: 140, hr_zones: zones.merge("source" => "fit"))
    estimated = create(:activity, avg_hr: 140, started_at: Time.utc(2016, 1, 1), local_started_at: Time.utc(2016, 1, 1), hr_zones: zones.merge("source" => "estimated"))

    get run_path(run)

    assert_select "dd", text: "130–149"
    assert_select "span", text: "Estimated zones", count: 0

    get run_path(estimated)

    assert_select "dd", text: "130–149"
    assert_select "p span", text: "Estimated zones"
    assert_select "p", text: /from before your watch recorded its zones/
  end

  test "an estimated run after the first recorded zones does not claim to predate them" do
    zones = {"floors" => [90, 110, 130, 150, 170], "max_hr" => 190, "seconds" => [60, 180, 360, 0, 0]}
    create(:activity, started_at: Time.utc(2018, 1, 1), local_started_at: Time.utc(2018, 1, 1), hr_zones: zones.merge("source" => "fit"))
    run = create(:activity, avg_hr: 140, hr_zones: zones.merge("source" => "estimated"))

    get run_path(run)

    assert_select "p", text: /has no recorded zones/
    assert_select "p", text: /before your watch/, count: 0
  end
end
