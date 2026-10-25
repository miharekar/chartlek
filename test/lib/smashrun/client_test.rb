require "test_helper"

class Smashrun::ClientTest < ActiveSupport::TestCase
  LOGIN_URL = Smashrun::Client::LOGIN_URL
  BASE_URL = Smashrun::Client::BASE_URL

  setup do
    @original_sleeper = Smashrun::Client.sleeper
    @sleeps = []
    Smashrun::Client.sleeper = ->(seconds) { @sleeps << seconds }
    @client = Smashrun::Client.new(email: "runner@example.com", password: "s3cret-pass")
  end

  teardown { Smashrun::Client.sleeper = @original_sleeper }

  test "logs in lazily and returns the parsed activities" do
    login = stub_login
    list = stub_request(:get, "#{BASE_URL}/my/activities").with(headers: {"Authorization" => "Bearer fake-access-token"}).to_return(body: file_fixture("smashrun/activities.json").read)

    assert_not_requested login
    activities = @client.activities

    assert_equal [1000001, 1000002], activities.pluck("activityId")
    assert_requested list
  end

  test "sends the login body as json" do
    login = stub_login.with(
      headers: {"Content-Type" => "application/json; charset=utf-8"},
      body: {loginEmail: "runner@example.com", loginPassword: "s3cret-pass", clientId: "client", scopes: "read_activity", isToken: true}.to_json
    )
    stub_request(:get, "#{BASE_URL}/my/activities").to_return(body: "[]")

    @client.activities

    assert_requested login
  end

  test "returns the raw activity body" do
    stub_login
    body = file_fixture("smashrun/activity.json").read
    stub_request(:get, "#{BASE_URL}/my/activities/1000002").to_return(body:)

    assert_equal body, @client.activity(1000002)
  end

  test "logs in once for several calls" do
    login = stub_login
    stub_request(:get, /my\/activities/).to_return(body: "[]")

    2.times { @client.activities }

    assert_requested login, times: 1
  end

  test "logs in again once after a 401" do
    login = stub_login
    stub_request(:get, "#{BASE_URL}/my/activities").to_return({status: 401}, {status: 200, body: "[]"})

    assert_equal [], @client.activities

    assert_requested login, times: 2
  end

  test "raises after a second 401" do
    stub_login
    stub_request(:get, "#{BASE_URL}/my/activities").to_return(status: 401)

    assert_raises(Smashrun::Client::Error) { @client.activities }
  end

  test "raises without leaking credentials when the login fails" do
    stub_login(file_fixture("smashrun/login_failed.json").read)

    error = assert_raises(Smashrun::Client::Error) { @client.activities }

    assert_no_match(/runner@example\.com|s3cret-pass/, error.message)
    assert_no_match(/runner@example\.com|s3cret-pass/, @client.inspect)
  end

  test "raises when the login returns no token" do
    stub_login({info: {isFailed: false, failCode: 0}, results: {auth: {}}}.to_json)

    assert_raises(Smashrun::Client::Error) { @client.activities }
  end

  test "ignores the login info message when the login succeeds" do
    stub_login
    stub_request(:get, "#{BASE_URL}/my/activities").to_return(body: "[]")

    assert_equal [], @client.activities
  end

  test "spaces api calls 15 seconds apart" do
    stub_login
    stub_request(:get, /my\/activities/).to_return(body: "[]")

    2.times { @client.activities }

    assert_equal 1, @sleeps.size
    assert_in_delta 15, @sleeps.first, 0.5
  end

  test "retries 429 and 5xx with exponential backoff" do
    stub_login
    stub_request(:get, "#{BASE_URL}/my/activities").to_return({status: 429}, {status: 503}, {status: 200, body: "[]"})

    assert_equal [], @client.activities

    assert_equal [2, 4], @sleeps.select { it >= 2 && it <= 4 }
  end

  test "retries transient network errors with backoff" do
    stub_login
    stub_request(:get, "#{BASE_URL}/my/activities").to_raise(Net::ReadTimeout).then.to_raise(Errno::ECONNRESET).then.to_return(body: "[]")

    assert_equal [], @client.activities
  end

  test "gives up after five attempts" do
    stub_login
    list = stub_request(:get, "#{BASE_URL}/my/activities").to_return(status: 500)

    assert_raises(Smashrun::Client::Error) { @client.activities }

    assert_requested list, times: 5
  end

  private
  def stub_login(body = file_fixture("smashrun/login.json").read)
    stub_request(:post, LOGIN_URL).to_return(body:)
  end
end
