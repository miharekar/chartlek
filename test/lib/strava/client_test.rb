require "test_helper"

class Strava::ClientTest < ActiveSupport::TestCase
  TOKEN_URL = "https://www.strava.com/oauth/token"
  ACTIVITIES_URL = "https://www.strava.com/api/v3/athlete/activities"
  REDIRECT_URI = "https://run.example.test/strava/callback"

  setup do
    @profile = Profile.instance
    @client = Strava::Client.new(client_id: "123", client_secret: "test-secret", profile: @profile)
  end

  def token(access, refresh, expires_in: 6.hours)
    {access_token: access, refresh_token: refresh, expires_at: expires_in.from_now.to_i}.to_json
  end

  def connect(access: "access-1", refresh: "refresh-1", expires_in: 6.hours)
    @profile.store_strava_tokens(access_token: access, refresh_token: refresh, expires_at: expires_in.from_now.to_i)
  end

  test "builds the authorization URL" do
    query = URI.decode_www_form(URI(@client.authorize_url(REDIRECT_URI, state: "abc")).query).to_h

    assert_equal({"client_id" => "123", "redirect_uri" => REDIRECT_URI, "response_type" => "code", "approval_prompt" => "auto", "scope" => "activity:read_all", "state" => "abc"}, query)
  end

  test "exchanges the code and stores both tokens encrypted" do
    stub_request(:post, TOKEN_URL).with(body: {client_id: "123", client_secret: "test-secret", code: "the-code", grant_type: "authorization_code"}).to_return(body: token("access-1", "refresh-1"))

    @client.authorize("the-code")

    profile = Profile.find(@profile.id)
    assert profile.strava_connected?
    assert_equal "access-1", profile.strava_access_token
    assert_equal "refresh-1", profile.strava_refresh_token
    raw = Profile.connection.select_one("SELECT strava_access_token, strava_refresh_token FROM profiles WHERE id = #{profile.id}")
    assert_not_includes raw.values.join, "access-1"
    assert_not_includes raw.values.join, "refresh-1"
  end

  test "pages through all activities with the stored token" do
    connect
    pages = [[{id: 1}, {id: 2}], [{id: 3}], []].each_with_index.map do |activities, index|
      stub_request(:get, ACTIVITIES_URL).with(query: {page: (index + 1).to_s, per_page: "200"}, headers: {"Authorization" => "Bearer access-1"}).to_return(body: activities.to_json)
    end

    assert_equal [1, 2, 3], @client.activities.pluck("id")
    pages.each { assert_requested it }
    assert_not_requested :post, TOKEN_URL
  end

  test "passes the after filter" do
    connect
    stub = stub_request(:get, ACTIVITIES_URL).with(query: {page: "1", per_page: "200", after: "1700000000"}).to_return(body: [{id: 1}].to_json)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "2")).to_return(body: [].to_json)

    assert_equal [1], @client.activities(after: 1_700_000_000).pluck("id")
    assert_requested stub
  end

  test "refreshes a token expiring within five minutes and saves the rotated refresh token" do
    connect(expires_in: 4.minutes)
    refresh = stub_request(:post, TOKEN_URL).with(body: {client_id: "123", client_secret: "test-secret", refresh_token: "refresh-1", grant_type: "refresh_token"}).to_return(body: token("access-2", "refresh-2"))
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1"), headers: {"Authorization" => "Bearer access-2"}).to_return(body: [{id: 1}].to_json)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "2")).to_return(body: [].to_json)

    assert_equal [1], @client.activities.pluck("id")

    assert_requested refresh, times: 1
    profile = Profile.find(@profile.id)
    assert_equal "access-2", profile.strava_access_token
    assert_equal "refresh-2", profile.strava_refresh_token
    assert_in_delta 6.hours.from_now.to_f, profile.strava_token_expires_at.to_f, 5
  end

  test "uses a token another process already refreshed and keeps the connection" do
    connect(expires_in: 1.minute)
    Profile.find(@profile.id).store_strava_tokens(access_token: "access-2", refresh_token: "refresh-2", expires_at: 6.hours.from_now.to_i)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1"), headers: {"Authorization" => "Bearer access-2"}).to_return(body: [{id: 1}].to_json)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "2")).to_return(body: [].to_json)

    assert_equal [1], @client.activities.pluck("id")

    assert_not_requested :post, TOKEN_URL
    assert Profile.find(@profile.id).strava_connected?
    assert_equal "refresh-2", Profile.find(@profile.id).strava_refresh_token
  end

  test "a rejected refresh after another process rotated the token uses the new token and keeps the connection" do
    connect(expires_in: 1.minute)
    other = Profile.find(@profile.id)
    stub_request(:post, TOKEN_URL).to_return do
      other.store_strava_tokens(access_token: "access-2", refresh_token: "refresh-2", expires_at: 6.hours.from_now.to_i)
      {status: 400, body: {message: "Bad Request"}.to_json}
    end
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1"), headers: {"Authorization" => "Bearer access-2"}).to_return(body: [{id: 1}].to_json)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "2")).to_return(body: [].to_json)

    assert_equal [1], @client.activities.pluck("id")

    assert_requested :post, TOKEN_URL, times: 1
    assert_equal "refresh-2", Profile.find(@profile.id).strava_refresh_token
    assert Profile.find(@profile.id).strava_connected?
  end

  test "a rejected refresh after another process cleared the connection raises NotConnected" do
    connect(expires_in: 1.minute)
    stub_request(:post, TOKEN_URL).to_return do
      Profile.find(@profile.id).disconnect_strava
      {status: 400, body: "{}"}
    end

    assert_raises(Strava::Client::NotConnected) { @client.activities }
  end

  test "the token request is not made inside a transaction" do
    connect(expires_in: 1.minute)
    baseline = Profile.connection.open_transactions
    open_transactions = nil
    stub_request(:post, TOKEN_URL).to_return do
      open_transactions = Profile.connection.open_transactions
      {body: token("access-2", "refresh-2")}
    end
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1")).to_return(body: [].to_json)

    @client.activities

    assert_equal baseline, open_transactions
  end

  test "a timeout on refresh propagates and keeps the connection" do
    connect(expires_in: 1.minute)
    stub_request(:post, TOKEN_URL).to_timeout

    assert_raises(Net::OpenTimeout) { @client.activities }

    assert Profile.find(@profile.id).strava_connected?
  end

  test "requests use short explicit timeouts" do
    assert_equal 10, Strava::Client::TIMEOUT
  end

  test "a refresh that finds the connection already cleared raises NotConnected without a request" do
    connect(expires_in: 1.minute)
    Profile.find(@profile.id).disconnect_strava

    assert_raises(Strava::Client::NotConnected) { @client.activities }
    assert_not_requested :post, TOKEN_URL
  end

  test "keeps a token that is valid for longer than five minutes" do
    connect(expires_in: 6.minutes)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1")).to_return(body: [].to_json)

    @client.activities

    assert_not_requested :post, TOKEN_URL
  end

  test "a 401 on the activities clears the connection" do
    connect
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1")).to_return(status: 401, body: {message: "Authorization Error"}.to_json)

    assert_raises(Strava::Client::NotConnected) { @client.activities }

    assert_not Profile.find(@profile.id).strava_connected?
    assert_nil Profile.find(@profile.id).strava_access_token
  end

  test "a revoked refresh clears the connection" do
    connect(expires_in: 1.minute)
    stub_request(:post, TOKEN_URL).to_return(status: 400, body: {message: "Bad Request"}.to_json)

    assert_raises(Strava::Client::NotConnected) { @client.activities }

    assert_not Profile.find(@profile.id).strava_connected?
  end

  test "a server error on refresh keeps the connection" do
    connect(expires_in: 1.minute)
    stub_request(:post, TOKEN_URL).to_return(status: 503, body: "down")

    assert_raises(Strava::Client::Error) { @client.activities }

    assert Profile.find(@profile.id).strava_connected?
  end

  test "raises NotConnected without tokens and makes no request" do
    assert_raises(Strava::Client::NotConnected) { @client.activities }
    assert_not_requested :any, /strava\.com/
  end

  test "raises with the status and never the secret" do
    stub_request(:post, TOKEN_URL).to_return(status: 400, body: {message: "Bad Request"}.to_json)

    error = assert_raises(Strava::Client::Error) { @client.authorize("bad") }

    assert_match "400", error.message
    assert_no_match "test-secret", error.message
  end

  test "inspect hides credentials" do
    assert_equal "#<Strava::Client>", @client.inspect
  end
end
