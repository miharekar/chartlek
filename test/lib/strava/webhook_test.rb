require "test_helper"

class Strava::WebhookTest < ActiveSupport::TestCase
  ENV_A = {"SECRET_KEY_BASE" => "secret-a"}

  test "the tokens are pinned HMAC-SHA256 digests, so an upgrade can't change the URL" do
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", "secret-a", "strava_webhook.path"), Strava::Webhook.token(ENV_A)
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", "secret-a", "strava_webhook.verify"), Strava::Webhook.verify_token(ENV_A)
    assert_match(/\A\h{64}\z/, Strava::Webhook.token(ENV_A))
  end

  test "the path and verify tokens differ, and a new secret changes both" do
    assert_not_equal Strava::Webhook.token(ENV_A), Strava::Webhook.verify_token(ENV_A)
    assert_not_equal Strava::Webhook.token(ENV_A), Strava::Webhook.token({"SECRET_KEY_BASE" => "secret-b"})
  end

  test "there are no tokens without SECRET_KEY_BASE" do
    assert_nil Strava::Webhook.token({"SECRET_KEY_BASE" => ""})
    assert_nil Strava::Webhook.verify_token({})
  end

  test "builds the callback URL from the host" do
    assert_equal "https://hooks.example.test/strava/webhook/#{Strava::Webhook.token(ENV_A)}", Strava::Webhook.callback_url("hooks.example.test", ENV_A)
  end
end
