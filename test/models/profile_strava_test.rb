require "test_helper"

class ProfileStravaTest < ActiveSupport::TestCase
  test "stores, reports and clears the connection" do
    profile = Profile.instance
    assert_not profile.strava_connected?

    profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    assert profile.strava_connected?
    profile.update!(strava_gear_synced_at: Time.current, strava_gear_attempts: 1)

    profile.disconnect_strava
    assert_not profile.strava_connected?
    assert_nil profile.strava_token_expires_at
    assert_nil profile.strava_gear_synced_at
    assert_equal 0, profile.strava_gear_attempts
  end

  test "tokens the current keys can't decrypt are cleared on load" do
    profile = Profile.instance
    other_keys = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("another key")
    ActiveRecord::Encryption.with_encryption_context(key_provider: other_keys) do
      profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      profile.update!(strava_scope: "activity:read_all")
    end

    profile = Profile.instance

    assert_not profile.strava_connected?
    assert_nil profile.strava_access_token
    assert_nil profile.strava_token_expires_at
    assert_nil profile.strava_scope
    assert_nil Profile.connection.select_value("SELECT strava_refresh_token FROM profiles")

    profile.store_strava_tokens(access_token: "a2", refresh_token: "r2", expires_at: 1.hour.from_now.to_i)
    assert_equal "r2", Profile.instance.strava_refresh_token
  end

  test "readable tokens are left alone" do
    Profile.instance.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)

    assert_equal "r", Profile.instance.strava_refresh_token
  end

  test "missing encryption keys keep failing and leave the tokens" do
    Profile.instance.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    primary_key = ActiveRecord::Encryption.config.primary_key

    begin
      ActiveRecord::Encryption.config.primary_key = nil
      ActiveRecord::Encryption.with_encryption_context(key_provider: nil) do
        assert_raises(ActiveRecord::Encryption::Errors::Configuration) { Profile.instance }
      end
    ensure
      ActiveRecord::Encryption.config.primary_key = primary_key
    end

    assert_equal "r", Profile.instance.strava_refresh_token
  end

  test "gear access needs a connection and the profile scope" do
    profile = Profile.instance
    profile.update!(strava_scope: "activity:read_all,profile:read_all")
    assert_not profile.strava_gear_access?
    assert_not profile.strava_reconnect?

    profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    assert profile.strava_gear_access?

    profile.update!(strava_scope: "activity:read_all")
    assert profile.strava_reconnect?

    profile.disconnect_strava
    assert_nil profile.strava_scope
  end
end
