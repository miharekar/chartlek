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
    output, = capture_io { probe.run }

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
    capture_io { probe(client).run }

    assert_equal 0o600, File.stat(@path).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(@path)).mode & 0o777
    assert_operator client.request_count, :<=, 70
  end

  private
  def probe(client = Garmin::Client.new(key: "test-key"))
    Garmin::Probe.new(client:, first_run_on: Date.current - 3000, path: @path)
  end
end
