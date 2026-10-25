require "test_helper"

class Strava::ClientTest < ActiveSupport::TestCase
  TOKEN_URL = "https://www.strava.com/oauth/token"
  ACTIVITIES_URL = "https://www.strava.com/api/v3/athlete/activities"
  REDIRECT_URI = "http://127.0.0.1:8137/strava/callback"

  setup { @client = Strava::Client.new(client_id: "123", client_secret: "test-secret") }

  test "builds the authorization URL" do
    query = URI.decode_www_form(URI(@client.authorize_url(REDIRECT_URI, state: "abc")).query).to_h

    assert_equal({"client_id" => "123", "redirect_uri" => REDIRECT_URI, "response_type" => "code", "approval_prompt" => "auto", "scope" => "activity:read_all", "state" => "abc"}, query)
  end

  test "exchanges the code and pages through all activities" do
    token = stub_request(:post, TOKEN_URL).with(body: {client_id: "123", client_secret: "test-secret", code: "the-code", grant_type: "authorization_code"}).to_return(body: {access_token: "access-1"}.to_json)
    pages = [[{id: 1}, {id: 2}], [{id: 3}], []].each_with_index.map do |activities, index|
      stub_request(:get, ACTIVITIES_URL).with(query: {page: (index + 1).to_s, per_page: "200"}, headers: {"Authorization" => "Bearer access-1"}).to_return(body: activities.to_json)
    end

    @client.authorize("the-code")

    assert_equal [1, 2, 3], @client.activities.pluck("id")
    assert_requested token
    pages.each { assert_requested it }
  end

  test "raises with the status and never the secret" do
    stub_request(:post, TOKEN_URL).to_return(status: 400, body: {message: "Bad Request"}.to_json)

    error = assert_raises(Strava::Client::Error) { @client.authorize("bad") }

    assert_match "400", error.message
    assert_no_match "test-secret", error.message
  end

  test "raises when an activities page fails" do
    stub_request(:post, TOKEN_URL).to_return(body: {access_token: "access-1"}.to_json)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1")).to_return(status: 401, body: {message: "Authorization Error"}.to_json)
    @client.authorize("the-code")

    error = assert_raises(Strava::Client::Error) { @client.activities }

    assert_match "401", error.message
  end

  test "inspect hides credentials" do
    assert_equal "#<Strava::Client>", @client.inspect
  end
end
