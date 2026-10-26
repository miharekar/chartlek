require "test_helper"

class ProfileStravaTest < ActiveSupport::TestCase
  test "stores, reports and clears the connection" do
    profile = Profile.instance
    assert_not profile.strava_connected?

    profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    assert profile.strava_connected?

    profile.disconnect_strava
    assert_not profile.strava_connected?
    assert_nil profile.strava_token_expires_at
  end
end
