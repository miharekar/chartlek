require "test_helper"
require_relative "api_stubs"

class Garmin::ClientTest < ActiveSupport::TestCase
  include GarminApiStubs

  setup do
    @client = Garmin::Client.new(key: "test-key")
    @original_cache = Rails.cache
  end

  teardown { Rails.cache = @original_cache }

  test "exchanges the key for a bearer token and uses it" do
    token = stub_token
    data = stub_request(:get, "#{BASE_URL}/userprofile-service/userprofile/settings").with(headers: {"Authorization" => /\ABearer .+\.sig\z/}).to_return(body: "{}")

    @client.profile_settings

    assert_requested token.with(headers: {"Authorization" => "ApiKey test-key"})
    assert_requested data
  end

  test "sends the activity search parameters" do
    stub_token
    page = stub_page(200, [])

    @client.activities(start: 200, limit: 100)

    assert_requested page
  end

  test "caches the token until an hour before expiry" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    token = stub_token
    stub_settings

    2.times { @client.profile_settings }

    assert_requested token, times: 1
  end

  test "does not cache a token that is about to expire" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    token = stub_request(:post, /personal-api-key\/token/).to_return(body: fake_jwt(exp: 30.minutes.from_now))
    stub_settings

    2.times { @client.profile_settings }

    assert_requested token, times: 2
  end

  test "re-exchanges the key once after a 401" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    token = stub_token
    stub_request(:get, /userprofile/).to_return({status: 401}, {status: 200, body: "{}"})

    assert_equal({}, @client.profile_settings)

    assert_requested token, times: 2
  end

  test "raises after a second 401" do
    stub_token
    stub_request(:get, /userprofile/).to_return(status: 401)

    assert_raises(Garmin::Client::Error) { @client.profile_settings }
  end

  test "raises InvalidKey when the exchange is rejected" do
    [401, 403].each do |status|
      WebMock.reset!
      stub_token(status:)

      assert_raises(Garmin::Client::InvalidKey) { Garmin::Client.new(key: "test-key").profile_settings }
    end
  end

  test "retries 429 and 5xx with exponential backoff" do
    stub_token
    stub_request(:get, /userprofile/).to_return({status: 429}, {status: 503}, {status: 200, body: "{}"})

    assert_equal({}, @client.profile_settings)

    assert_equal [2, 4], @sleeps.select { it >= 2 }
  end

  test "retries transient network errors with backoff" do
    [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, OpenSSL::SSL::SSLError, SocketError].each do |error|
      WebMock.reset!
      @sleeps.clear
      stub_token
      stub_request(:get, /userprofile/).to_raise(error).then.to_raise(error).then.to_return(status: 200, body: "{}")

      assert_equal({}, Garmin::Client.new(key: "test-key").profile_settings, error.name)
      assert_equal [2, 4], @sleeps.select { it >= 2 }, error.name
    end
  end

  test "retries a network error on the token exchange" do
    stub_request(:post, /personal-api-key\/token/).to_raise(Net::ReadTimeout).then.to_return(body: fake_jwt)
    stub_settings

    assert_equal "metric", @client.profile_settings["measurementSystem"]
  end

  test "raises a network error after five attempts" do
    stub_token
    data = stub_request(:get, /userprofile/).to_raise(Net::ReadTimeout)

    assert_raises(Net::ReadTimeout) { @client.profile_settings }

    assert_requested data, times: 5
  end

  test "gives up after five attempts" do
    stub_token
    data = stub_request(:get, /userprofile/).to_return(status: 500)

    assert_raises(Garmin::Client::Error) { @client.profile_settings }

    assert_requested data, times: 5
  end

  test "throttles to one request per second" do
    stub_token
    stub_settings

    @client.profile_settings

    assert @sleeps.any? { it > 0 && it <= 1 }
  end

  test "never exposes the key" do
    stub_token(status: 401)

    error = assert_raises(Garmin::Client::InvalidKey) { @client.profile_settings }

    assert_no_match(/test-key/, error.message)
    assert_no_match(/test-key/, @client.inspect)
  end
end
