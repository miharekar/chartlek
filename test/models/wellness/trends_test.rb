require "test_helper"

class Wellness::TrendsTest < ActiveSupport::TestCase
  test "no data without a day that holds a value" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), raw: {"summary" => {}})

    assert_not Wellness::Trends.new.data?
  end

  test "days are dense so a missing day is a nil gap, and empty markers are skipped" do
    WellnessDay.create!(date: Date.new(2024, 3, 1), raw: {"summary" => {}})
    WellnessDay.create!(date: Date.new(2024, 3, 2), resting_hr: 50, stress_avg: 30)
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52, hrv_last_night: 60, hrv_status: "BALANCED")

    trends = Wellness::Trends.new
    payload = trends.payload

    assert_equal [50, nil, nil, 52], payload[:columns][:rhr]
    assert_equal [30, nil, nil, nil], payload[:columns][:stress]
    assert_equal [nil, nil, nil, 60], payload[:columns][:hrv]
    assert_equal [nil, nil, nil, "BALANCED"], payload[:columns][:status]
    assert_not payload[:columns].key?(:weight)
    assert_equal Time.utc(2024, 3, 2).to_i * 1000, payload[:start]
    assert_equal [Time.utc(2024, 3, 2).to_i * 1000, Time.utc(2024, 3, 5).to_i * 1000], payload[:domain]
    assert_equal %i[rhr hrv stress], trends.charts
  end

  test "the window defaults to the last year and follows from and to" do
    WellnessDay.create!(date: Date.new(2020, 1, 1), resting_hr: 50)
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52)
    ms = ->(y, m, d) { Time.utc(y, m, d).to_i * 1000 }

    assert_equal [ms.(2023, 3, 5), ms.(2024, 3, 6)], Wellness::Trends.new.payload[:window]
    assert_equal [ms.(2021, 1, 1), ms.(2021, 2, 2)], Wellness::Trends.new(from: "2021-01-01", to: "2021-02-01").payload[:window]
    assert_equal Wellness::Trends.new.payload[:window], Wellness::Trends.new(from: "nope", to: 5).payload[:window]
  end

  test "VDOT comes from the top runs" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52)
    create(:activity, local_started_at: Time.utc(2024, 3, 1, 7), started_at: Time.utc(2024, 3, 1, 6))
    create(:activity, local_started_at: Time.utc(2024, 3, 2, 7), started_at: Time.utc(2024, 3, 2, 6))

    trends = Wellness::Trends.new

    assert_equal [[Time.utc(2024, 3, 1, 7).to_i * 1000, 40.01], [Time.utc(2024, 3, 2, 7).to_i * 1000, 40.01]], trends.payload[:vdot]
    assert_not trends.payload.key?(:vo2max)
    assert_includes trends.charts, :vdot
  end

  test "there is no data when the wellness columns hold nothing a chart can draw" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), hrv_status: "BALANCED", hrv_baseline_low: 50, body_battery_wake: 80, body_battery_high: 90)

    assert_not Wellness::Trends.new.data?
  end

  test "there is no data without wellness days even when runs have a VDOT" do
    create(:activity)

    assert_not Wellness::Trends.new.data?
  end

  test "heart rate zone time is summed per week starting Monday and empty weeks are left out" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52)
    create(:activity, local_started_at: Time.utc(2024, 3, 4, 7), started_at: Time.utc(2024, 3, 4, 6), summary: {"hrTimeInZone_1" => 100.4, "hrTimeInZone_3" => 200})
    create(:activity, local_started_at: Time.utc(2024, 3, 10, 7), started_at: Time.utc(2024, 3, 10, 6), summary: {"hrTimeInZone_1" => 50, "hrTimeInZone_5" => 10})
    create(:activity, local_started_at: Time.utc(2024, 3, 11, 7), started_at: Time.utc(2024, 3, 11, 6), summary: {"hrTimeInZone_1" => 0})
    create(:activity, local_started_at: Time.utc(2024, 3, 18, 7), started_at: Time.utc(2024, 3, 18, 6))

    assert_equal [[Time.utc(2024, 3, 4).to_i * 1000, 150, 0, 200, 0, 10]], Wellness::Trends.new.payload[:zones]
  end

  test "overlay holds only the resting hr and hrv series, dense, from the first day" do
    WellnessDay.create!(date: Date.new(2024, 3, 1), raw: {"summary" => {}})
    WellnessDay.create!(date: Date.new(2024, 3, 2), resting_hr: 50, stress_avg: 30)
    WellnessDay.create!(date: Date.new(2024, 3, 4), resting_hr: 52, hrv_last_night: 60, weight_kg: 70.0)

    overlay = Wellness::Trends.new.overlay

    assert_equal %i[start rhr hrv], overlay.keys
    assert_equal Time.utc(2024, 3, 2).to_i * 1000, overlay[:start]
    assert_equal [50, nil, 52], overlay[:rhr]
    assert_equal [nil, nil, 60], overlay[:hrv]
  end

  test "no overlay without either series" do
    assert_nil Wellness::Trends.new.overlay

    WellnessDay.create!(date: Date.new(2024, 3, 2), stress_avg: 30)

    assert_nil Wellness::Trends.new.overlay
  end
end
