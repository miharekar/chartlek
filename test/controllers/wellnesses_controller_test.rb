require "test_helper"

class WellnessesControllerTest < ActionDispatch::IntegrationTest
  test "renders an empty state without wellness data" do
    get wellness_path

    assert_response :success
    assert_select "[data-controller='wellness']", false
    assert_select "p", /No wellness data yet/
    assert_select "code", "docker compose exec chartlek bin/rails wellness:backfill"
  end

  test "renders the empty state when no column can make a chart" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), hrv_status: "BALANCED", body_battery_wake: 80)

    get wellness_path

    assert_response :success
    assert_select "[data-controller='wellness']", false
    assert_select "p", /No wellness data yet/
  end

  test "renders a card per chart that has data" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52, weight_kg: 70.5)

    get wellness_path

    assert_response :success
    assert_select "[data-controller='wellness'][data-wellness-payload-value]"
    assert_select "[data-wellness-target=chart]", count: 2
    assert_select "[data-chart=rhr]"
    assert_select "[data-chart=weight]"
    assert_select "[data-chart=hrv]", false
    assert_select "[role=group][aria-label=Window] button[data-action='wellness#preset'][aria-pressed]", count: 5
    assert_select "nav a[href='/wellness']", "Wellness"
  end

  test "the sleep chart shows only with sleep data" do
    WellnessDay.create!(date: Date.new(2024, 3, 5), resting_hr: 52)

    get wellness_path
    assert_select "[data-chart=sleep]", false

    WellnessDay.create!(date: Date.new(2024, 3, 6), sleep_s: 26_000, sleep_score: 80, raw: {"sleep" => {"sleepNeed" => {"actual" => 480}}})
    get wellness_path
    assert_select "[data-chart=sleep]"
    assert_includes response.body, "sleep_need"
    assert_select "[data-chart=timing]", false
  end

  test "the timing chart shows with bedtime and wake time" do
    ms = ->(*time) { Time.utc(*time).to_i * 1000 }
    WellnessDay.create!(date: Date.new(2024, 3, 6), sleep_s: 26_000, raw: {"sleep" => {"sleepStartTimestampLocal" => ms.(2024, 3, 5, 23, 10), "sleepEndTimestampLocal" => ms.(2024, 3, 6, 6, 30)}})

    get wellness_path

    assert_select "[data-chart=timing]"
  end
end
