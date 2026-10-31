require "test_helper"

class StravaWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous = ENV["SECRET_KEY_BASE"]
    ENV["SECRET_KEY_BASE"] = "controller-test-secret"
    @path = "/strava/webhook/#{Strava::Webhook.token}"
    @verify = Strava::Webhook.verify_token
  end

  teardown { ENV["SECRET_KEY_BASE"] = @previous }

  test "echoes the challenge for the right verify token" do
    get @path, params: {"hub.mode" => "subscribe", "hub.challenge" => "15f7d1a91c1f40f8a748fd134752feb3", "hub.verify_token" => @verify}

    assert_response :success
    assert_equal({"hub.challenge" => "15f7d1a91c1f40f8a748fd134752feb3"}, response.parsed_body)
  end

  test "a wrong, missing or empty verify token is 404" do
    [{"hub.verify_token" => "nope"}, {}, {"hub.verify_token" => ""}].each do |extra|
      get @path, params: {"hub.mode" => "subscribe", "hub.challenge" => "abc"}.merge(extra)

      assert_response :not_found
    end
  end

  test "a request that isn't a subscribe is 404" do
    get @path, params: {"hub.mode" => "unsubscribe", "hub.challenge" => "abc", "hub.verify_token" => @verify}
    assert_response :not_found

    get @path
    assert_response :not_found
  end

  test "without the gate both verbs are 404" do
    get "/strava/webhook", params: {"hub.mode" => "subscribe", "hub.challenge" => "abc", "hub.verify_token" => @verify}
    assert_response :not_found

    post "/strava/webhook", params: {object_type: "activity", aspect_type: "create", object_id: 1}, as: :json
    assert_response :not_found
    assert_no_enqueued_jobs
  end

  test "answers 200 with an empty body for every kind of event" do
    events = [
      {object_type: "activity", aspect_type: "create", object_id: 1, owner_id: 2, subscription_id: 3, event_time: 4, updates: {}},
      {object_type: "activity", aspect_type: "update", object_id: 1, updates: {title: "New"}},
      {object_type: "activity", aspect_type: "delete", object_id: 1},
      {object_type: "athlete", aspect_type: "update", object_id: 2, updates: {authorized: "false"}},
      {object_type: "athlete", aspect_type: "update", object_id: 2, updates: "garbage"},
      {object_type: "bogus", aspect_type: "nothing"},
      {}
    ]

    events.each do |event|
      post @path, params: event, as: :json

      assert_response :success
      assert_empty response.body
    end
  end

  test "posts need no CSRF token" do
    with_forgery_protection do
      post @path, params: {object_type: "activity", aspect_type: "create", object_id: 1}, as: :json
    end

    assert_response :success
  end

  test "an activity create queues a sync a minute out" do
    freeze_time do
      assert_enqueued_with(job: Activity::SyncJob, at: 1.minute.from_now) do
        post @path, params: {object_type: "activity", aspect_type: "create", object_id: 1}, as: :json
      end
    end
  end

  private
  def with_forgery_protection
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = old
  end
end
