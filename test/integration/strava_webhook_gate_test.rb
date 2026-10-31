require "test_helper"

class StravaWebhookGateTest < ActionDispatch::IntegrationTest
  CLOUDFLARE = {"Cf-Ray" => "8f1a2b3c4d5e-VIE"}
  HOOKS_HOST = "chartlek-hooks.rekar.eu"

  setup do
    @previous = ENV["SECRET_KEY_BASE"]
    ENV["SECRET_KEY_BASE"] = "gate-test-secret"
    @token = Strava::Webhook.token
    @challenge = {"hub.mode" => "subscribe", "hub.challenge" => "abc123", "hub.verify_token" => Strava::Webhook.verify_token}
  end

  teardown { ENV["SECRET_KEY_BASE"] = @previous }

  def blocked_paths
    wrong = "0" * 64

    ["/overview", "/up", "/", "/assets/application.css", "/strava/callback", "/strava/webhook", "/strava/webhook/", "/strava/webhook/#{wrong}", "/strava/webhook/#{@token}/", "/strava/webhook/#{@token}/../../overview", "/strava/webhook/#{@token}/..%2f..%2foverview", "/strava/webhook/..%2f..%2foverview", "/strava/webhook/%2e%2e/overview", "/strava/webhook/#{@token.upcase}", "/strava/webhook/#{@token}%2f", "/overview?next=/strava/webhook/#{@token}"]
  end

  test "a request with Cf-Ray gets a bare 404 for everything but the exact token path" do
    blocked_paths.each do |path|
      get path, headers: CLOUDFLARE

      assert_response :not_found, path
      assert_empty response.body, path
    end
  end

  test "a request for the hooks host gets a bare 404 for everything but the exact token path" do
    host! HOOKS_HOST

    blocked_paths.each do |path|
      get path

      assert_response :not_found, path
      assert_empty response.body, path
    end
  end

  test "POST to anything but the token path is a bare 404 from outside" do
    post "/strava/webhook", params: {object_type: "activity"}, headers: CLOUDFLARE, as: :json
    assert_response :not_found

    post "/sync", headers: CLOUDFLARE
    assert_response :not_found
  end

  test "requests without Cloudflare signals behave as before" do
    get "/up"
    assert_response :success

    get "/overview"
    assert_response :success

    get "/strava/webhook/#{"0" * 64}"
    assert_response :not_found
  end

  test "the webhook path without the token is 404 for everyone" do
    get "/strava/webhook", params: @challenge
    assert_response :not_found

    get "/strava/webhook", params: @challenge, headers: CLOUDFLARE
    assert_response :not_found
  end

  test "the right token reaches the controller with and without Cf-Ray" do
    [{}, CLOUDFLARE].each do |origin|
      get "/strava/webhook/#{@token}", params: @challenge, headers: origin

      assert_response :success
      assert_equal({"hub.challenge" => "abc123"}, response.parsed_body)
    end
  end

  test "the right token reaches the controller through the hooks host" do
    host! HOOKS_HOST
    get "/strava/webhook/#{@token}", params: @challenge

    assert_response :success
  end

  test "the rewritten path and the query string are all the app sees of the token path" do
    get "/strava/webhook/#{@token}", params: @challenge, headers: CLOUDFLARE

    assert_equal "/strava/webhook", request.path
    assert_not_includes request.original_fullpath, @token
    assert_not_includes request.fullpath, @token
    assert_includes request.fullpath, "hub.challenge=abc123"
  end

  test "no env key the app sees still carries the token after the rewrite" do
    seen = nil
    app = ->(env) { seen = env; [200, {}, []] }
    path = "/strava/webhook/#{@token}"
    env = Rack::MockRequest.env_for("#{path}?hub.mode=subscribe", "REQUEST_PATH" => path, "REQUEST_URI" => "#{path}?hub.mode=subscribe", "ORIGINAL_FULLPATH" => "#{path}?hub.mode=subscribe")

    StravaWebhookGate.new(app).call(env)

    assert_equal "/strava/webhook", seen["PATH_INFO"]
    assert_equal "/strava/webhook", seen["REQUEST_PATH"]
    assert_equal "/strava/webhook?hub.mode=subscribe", seen["REQUEST_URI"]
    assert_equal "/strava/webhook?hub.mode=subscribe", seen["ORIGINAL_FULLPATH"]
    assert_empty seen.select { |_, value| value.is_a?(String) && value.include?(@token) }
  end

  test "an event posted to the token path is accepted" do
    assert_enqueued_with(job: Activity::SyncJob) do
      post "/strava/webhook/#{@token}", params: {object_type: "activity", aspect_type: "create", object_id: 1}, headers: CLOUDFLARE, as: :json
    end

    assert_response :success
  end

  test "without SECRET_KEY_BASE no path is let through and outside requests are all 404" do
    ENV["SECRET_KEY_BASE"] = ""

    get "/strava/webhook/", params: @challenge, headers: CLOUDFLARE
    assert_response :not_found

    get "/up"
    assert_response :success
  end
end
