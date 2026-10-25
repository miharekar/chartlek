module GarminApiStubs
  extend ActiveSupport::Concern

  BASE_URL = "https://personal.connectapi.garmin.com"
  ACTIVITIES_URL = "#{BASE_URL}/activitylist-service/activities/search/activities"

  included do
    setup do
      @original_sleeper = Garmin::Client.sleeper
      @sleeps = []
      Garmin::Client.sleeper = ->(seconds) { @sleeps << seconds }
    end

    teardown { Garmin::Client.sleeper = @original_sleeper }
  end

  def fake_jwt(exp: 24.hours.from_now)
    [{alg: "none"}, {exp: exp.to_i}, "sig"].map { it.is_a?(Hash) ? Base64.urlsafe_encode64(it.to_json, padding: false) : it }.join(".")
  end

  def stub_token(status: 200)
    stub_request(:post, "#{BASE_URL}/personalapitoken-service/personal-api/personal-api-key/token").to_return(status:, body: fake_jwt)
  end

  def stub_settings
    stub_request(:get, "#{BASE_URL}/userprofile-service/userprofile/settings").to_return(status: 200, body: file_fixture("garmin/settings.json").read)
  end

  def garmin_summary(overrides = {})
    JSON.parse(file_fixture("garmin/activity.json").read).merge(overrides.stringify_keys)
  end

  def garmin_summaries(count, first_id: 9100000, **overrides)
    Array.new(count) { |i| garmin_summary(overrides.merge(activityId: first_id + i)) }
  end

  def stub_page(start, summaries)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("activityType" => "running", "start" => start.to_s, "limit" => "100")).to_return(status: 200, body: summaries.to_json)
  end
end
