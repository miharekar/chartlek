require "test_helper"
require "rake"

class StravaTaskTest < ActiveSupport::TestCase
  PUSH_URL = "https://www.strava.com/api/v3/push_subscriptions"
  HOST_URL = "https://hooks.example.test"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("strava:subscribe")
    Rake::Task["strava:subscribe"].reenable
    @previous = %w[SECRET_KEY_BASE STRAVA_CLIENT_ID STRAVA_SECRET].index_with { ENV[it] }
    ENV.update("SECRET_KEY_BASE" => "task-test-secret", "STRAVA_CLIENT_ID" => "123", "STRAVA_SECRET" => "test-secret")
    @callback_url = Strava::Webhook.callback_url("hooks.example.test")
  end

  teardown { @previous.each { |key, value| ENV[key] = value } }

  def listing(*subscriptions)
    stub_request(:get, PUSH_URL).with(query: hash_including({})).to_return(body: subscriptions.to_json)
  end

  test "keeps a subscription that already has the derived callback URL" do
    listing({id: 7, callback_url: @callback_url})

    out, = capture_io { Rake::Task["strava:subscribe"].invoke(HOST_URL) }

    assert_equal "Already subscribed 7 on hooks.example.test\n", out
    assert_not_requested :post, PUSH_URL
    assert_not_requested :delete, /push_subscriptions/
  end

  test "replaces a different subscription and prints the id and host only" do
    listing({id: 7, callback_url: "https://old.example.test/strava/webhook/abc"})
    stub_request(:delete, "#{PUSH_URL}/7").with(query: hash_including({})).to_return(status: 204)
    stub_request(:post, PUSH_URL).to_return(body: {id: 8}.to_json)

    out, = capture_io { Rake::Task["strava:subscribe"].invoke(HOST_URL) }

    assert_equal "Subscribed 8 on hooks.example.test\n", out
    assert_not_includes out, Strava::Webhook.token
  end

  test "a rejected subscription aborts without the URL" do
    listing
    stub_request(:post, PUSH_URL).to_return(status: 400, body: "nope")

    _, err = capture_io { assert_raises(SystemExit) { Rake::Task["strava:subscribe"].invoke(HOST_URL) } }

    assert_includes err, "400"
    assert_not_includes err, Strava::Webhook.token
  end
end
