require "test_helper"

class Activity::WeatherTest < ActiveSupport::TestCase
  URL = OpenMeteo::Client::ARCHIVE_URL

  setup do
    @original_sleeper = OpenMeteo::Client.sleeper
    OpenMeteo::Client.sleeper = ->(seconds) { }
  end

  teardown { OpenMeteo::Client.sleeper = @original_sleeper }

  test "stores the hour at the local midpoint with sunrise and sunset" do
    activity = create(:activity, local_started_at: Time.utc(2024, 3, 5, 9, 10), elapsed_s: 3600, start_lat: 46.05, start_lng: 14.5)
    request = stub_archive(date: "2024-03-05")

    activity.fetch_weather

    assert_requested request
    assert_equal({"temperature" => 10.0, "humidity" => 60, "wind" => 5.5, "precipitation" => 0.0, "code" => 3, "sunrise" => "2024-03-05T06:20", "sunset" => "2024-03-05T17:45"}, activity.reload.weather)
  end

  test "uses timer time when elapsed time is missing" do
    activity = create(:activity, local_started_at: Time.utc(2024, 3, 5, 9, 10), elapsed_s: nil, timer_s: 3000, start_lat: 46.05, start_lng: 14.5)
    stub_archive(date: "2024-03-05")

    activity.fetch_weather

    assert_equal 10.0, activity.reload.weather["temperature"]
  end

  test "requests the date of the midpoint when the run crosses midnight" do
    activity = create(:activity, local_started_at: Time.utc(2024, 3, 5, 23, 30), elapsed_s: 7200, start_lat: 46.05, start_lng: 14.5)
    request = stub_archive(date: "2024-03-06")

    activity.fetch_weather

    assert_requested request
    assert_equal 0.0, activity.reload.weather["temperature"]
  end

  test "leaves weather nil when the archive has no data yet" do
    activity = create(:activity, start_lat: 46.05, start_lng: 14.5)
    stub_archive(date: "2024-03-05", temperatures: [nil] * 24)

    activity.fetch_weather

    assert_nil activity.reload.weather
  end

  test "a run from the last days comes from the forecast and keeps that value" do
    started = Time.current.utc.beginning_of_day - 1.day + 9.hours
    activity = create(:activity, local_started_at: started, elapsed_s: 3600, start_lat: 46.05, start_lng: 14.5)
    forecast = stub_archive(date: started.to_date.iso8601, url: OpenMeteo::Client::FORECAST_URL)

    activity.fetch_weather

    assert_requested forecast
    assert_not_requested :get, URL
    assert_equal 10.0, activity.reload.weather["temperature"]
  end

  test "the archive takes over from the forecast after the lag" do
    recent = create(:activity, local_started_at: 4.days.ago.utc.beginning_of_day + 9.hours, elapsed_s: 3600, start_lat: 46.05, start_lng: 14.5)
    older = create(:activity, local_started_at: 6.days.ago.utc.beginning_of_day + 9.hours, elapsed_s: 3600, start_lat: 46.05, start_lng: 14.5)
    forecast = stub_archive(date: recent.local_started_at.to_date.iso8601, url: OpenMeteo::Client::FORECAST_URL)
    archive = stub_archive(date: older.local_started_at.to_date.iso8601)

    recent.fetch_weather
    older.fetch_weather

    assert_requested forecast, times: 1
    assert_requested archive, times: 1
  end

  test "a forecast with no data leaves weather nil so a later sync retries" do
    started = Time.current.utc.beginning_of_day - 1.day + 9.hours
    activity = create(:activity, local_started_at: started, elapsed_s: 3600, start_lat: 46.05, start_lng: 14.5)
    stub_archive(date: started.to_date.iso8601, url: OpenMeteo::Client::FORECAST_URL, temperatures: [nil] * 24)

    activity.fetch_weather

    assert_nil activity.reload.weather
  end

  test "skips indoor runs and runs without coordinates" do
    indoor = create(:activity, indoor: true, start_lat: 46.05, start_lng: 14.5)
    unlocated = create(:activity)

    assert_not indoor.weatherable?
    assert_not unlocated.weatherable?
    assert_nil indoor.fetch_weather
    assert_nil unlocated.fetch_weather
  end

  test "fetch_weather reports fetched, pending, skipped and failed runs" do
    ready = create(:activity, local_started_at: Time.utc(2024, 3, 5, 9, 10), start_lat: 46.05, start_lng: 14.5)
    pending = create(:activity, local_started_at: Time.utc(2024, 3, 6, 9, 10), start_lat: 46.05, start_lng: 14.5)
    broken = create(:activity, local_started_at: Time.utc(2024, 3, 7, 9, 10), start_lat: 46.05, start_lng: 14.5)
    done = create(:activity, local_started_at: Time.utc(2024, 3, 8, 9, 10), start_lat: 46.05, start_lng: 14.5, weather: {"temperature" => 1})
    create(:activity, indoor: true)
    stub_archive(date: "2024-03-05")
    stub_archive(date: "2024-03-06", temperatures: [nil] * 24)
    stub_request(:get, URL).with(query: hash_including(start_date: "2024-03-07")).to_return(status: 400)
    progress = []

    report = Activity.fetch_weather { progress << it }

    assert_equal({fetched: 1, pending: 1, skipped: 1, failed: {broken.external_id => "Open-Meteo responded 400"}}, report)
    assert_equal [{done: 1, total: 3}, {done: 2, total: 3}, {done: 3, total: 3}], progress
    assert_equal 10.0, ready.reload.weather["temperature"]
    assert_nil pending.reload.weather
    assert_equal({"temperature" => 1}, done.reload.weather)
  end

  private
  def stub_archive(date:, url: URL, temperatures: (0..23).map { it.to_f })
    temperatures = temperatures.each_with_index.map { |value, hour| (hour == 9) ? (value && 10.0) : value }
    hours = (0..23).map { format("%sT%02d:00", date, it) }

    stub_request(:get, url).with(query: hash_including(start_date: date)).to_return(body: {
      hourly: {
        time: hours, temperature_2m: temperatures, relative_humidity_2m: [60] * 24, wind_speed_10m: [5.5] * 24,
        precipitation: [0.0] * 24, weather_code: [3] * 24
      },
      daily: {sunrise: ["#{date}T06:20"], sunset: ["#{date}T17:45"]}
    }.to_json)
  end
end
