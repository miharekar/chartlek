require "test_helper"

class OpenMeteo::ClientTest < ActiveSupport::TestCase
  URL = OpenMeteo::Client::ARCHIVE_URL

  setup do
    @original_sleeper = OpenMeteo::Client.sleeper
    @sleeps = []
    OpenMeteo::Client.sleeper = ->(seconds) { @sleeps << seconds }
    @client = OpenMeteo::Client.new
  end

  teardown { OpenMeteo::Client.sleeper = @original_sleeper }

  test "sends rounded coordinates and the requested variables" do
    request = stub_request(:get, URL).with(query: {
      latitude: "10.12", longitude: "-20.35",
      start_date: "2016-08-20", end_date: "2016-08-20",
      hourly: "temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,weather_code",
      daily: "sunrise,sunset", timezone: "auto", wind_speed_unit: "kmh"
    }).to_return(body: {hourly: {temperature_2m: [12.5]}}.to_json)

    result = @client.weather(lat: 10.1234, lng: -20.3456, date: Date.new(2016, 8, 20))

    assert_requested request
    assert_equal [12.5], result.dig("hourly", "temperature_2m")
  end

  test "recent asks the forecast endpoint for the same variables" do
    request = stub_request(:get, OpenMeteo::Client::FORECAST_URL).with(query: {
      latitude: "10.12", longitude: "-20.35",
      start_date: "2016-08-20", end_date: "2016-08-20",
      hourly: "temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,weather_code",
      daily: "sunrise,sunset", timezone: "auto", wind_speed_unit: "kmh"
    }).to_return(body: {hourly: {temperature_2m: [9.5]}}.to_json)

    result = @client.weather(lat: 10.1234, lng: -20.3456, date: Date.new(2016, 8, 20), recent: true)

    assert_requested request
    assert_equal [9.5], result.dig("hourly", "temperature_2m")
  end

  test "spaces calls one second apart" do
    stub_request(:get, URL).with(query: hash_including({})).to_return(body: "{}")

    2.times { @client.weather(lat: 1, lng: 2, date: Date.new(2016, 8, 20)) }

    assert_equal 1, @sleeps.size
    assert_in_delta 1, @sleeps.first, 0.5
  end

  test "retries 429 and 5xx with exponential backoff" do
    stub_request(:get, URL).with(query: hash_including({})).to_return({status: 429}, {status: 502}, {status: 200, body: "{}"})

    assert_equal({}, @client.weather(lat: 1, lng: 2, date: Date.new(2016, 8, 20)))

    assert_equal [2, 4], @sleeps.select { it >= 2 }
  end

  test "retries transient network errors" do
    stub_request(:get, URL).with(query: hash_including({})).to_raise(Net::OpenTimeout).then.to_return(body: "{}")

    assert_equal({}, @client.weather(lat: 1, lng: 2, date: Date.new(2016, 8, 20)))
  end

  test "raises on a client error" do
    stub_request(:get, URL).with(query: hash_including({})).to_return(status: 400)

    assert_raises(OpenMeteo::Client::Error) { @client.weather(lat: 1, lng: 2, date: Date.new(2016, 8, 20)) }
  end
end
