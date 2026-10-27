require "test_helper"

class StravaConnectionsControllerTest < ActionDispatch::IntegrationTest
  TOKEN_URL = "https://www.strava.com/oauth/token"

  def start
    post strava_connection_path
    URI.decode_www_form(URI(response.location).query).to_h
  end

  test "create redirects to Strava with the callback URL, the scope and a state" do
    with_env("STRAVA_CLIENT_ID" => "123") { post strava_connection_path }

    uri = URI(response.location)
    query = URI.decode_www_form(uri.query).to_h
    assert_equal "www.strava.com", uri.host
    assert_equal "activity:read_all,profile:read_all", query["scope"]
    assert_equal "http://www.example.com/strava/callback", query["redirect_uri"]
    assert_equal "123", query["client_id"]
    assert query["state"].present?
  end

  test "the callback stores the tokens, queues the full link and redirects with a notice" do
    state = start["state"]
    stub_request(:post, TOKEN_URL).to_return(body: {access_token: "a-1", refresh_token: "r-1", expires_at: 6.hours.from_now.to_i}.to_json)

    assert_enqueued_with(job: Activity::StravaLinkJob, args: [{full: true}]) do
      get strava_callback_path(code: "the-code", state:, scope: "read,activity:read_all")
    end

    assert_redirected_to root_path
    assert_equal "Strava connected. Linking your runs.", flash[:notice]
    assert Profile.instance.strava_connected?
    assert_equal "r-1", Profile.instance.strava_refresh_token
  end

  test "a missing private scope is mentioned" do
    state = start["state"]
    stub_request(:post, TOKEN_URL).to_return(body: {access_token: "a", refresh_token: "r", expires_at: 6.hours.from_now.to_i}.to_json)

    get strava_callback_path(code: "c", state:, scope: "read,activity:read")

    assert_match "Private activities were not shared", flash[:notice]
    assert Profile.instance.strava_connected?
  end

  test "a grant without activity access stores nothing and queues nothing" do
    ["read", "", "profile:read_all"].each do |scope|
      state = start["state"]

      assert_no_enqueued_jobs do
        get strava_callback_path(code: "c", state:, scope:)
      end

      assert_match "activity access is needed", flash[:alert]
      assert_not Profile.instance.strava_connected?
    end
    assert_not_requested :post, TOKEN_URL
  end

  test "a grant with no scope parameter is rejected too" do
    state = start["state"]

    get strava_callback_path(code: "c", state:)

    assert_match "activity access is needed", flash[:alert]
    assert_not Profile.instance.strava_connected?
  end

  test "a state mismatch is rejected and stores nothing" do
    start

    get strava_callback_path(code: "the-code", state: "forged")

    assert_redirected_to root_path
    assert_match "state mismatch", flash[:alert]
    assert_not Profile.instance.strava_connected?
    assert_not_requested :post, TOKEN_URL
  end

  test "a callback without a prior start is rejected" do
    get strava_callback_path(code: "the-code", state: "anything")

    assert_match "state mismatch", flash[:alert]
    assert_not Profile.instance.strava_connected?
  end

  test "the state can be used only once" do
    state = start["state"]
    stub_request(:post, TOKEN_URL).to_return(body: {access_token: "a", refresh_token: "r", expires_at: 6.hours.from_now.to_i}.to_json)
    get strava_callback_path(code: "c", state:, scope: "activity:read_all")
    Profile.instance.disconnect_strava

    get strava_callback_path(code: "c", state:)

    assert_match "state mismatch", flash[:alert]
    assert_not Profile.instance.strava_connected?
  end

  test "a user who denies access sees a fixed message and stays disconnected" do
    start

    get strava_callback_path(error: "access_denied", state: "x")

    assert_equal "Strava connection was cancelled.", flash[:alert]
    assert_not Profile.instance.strava_connected?
  end

  test "an arbitrary error parameter is never echoed" do
    get strava_callback_path(error: "<b>Call me</b>")

    assert_equal "Strava connection was cancelled.", flash[:alert]
    assert_no_match "Call me", flash[:alert]
  end

  test "a failed token exchange stays disconnected" do
    state = start["state"]
    stub_request(:post, TOKEN_URL).to_return(status: 400, body: "{}")

    get strava_callback_path(code: "bad", state:, scope: "activity:read_all")

    assert_equal "Strava authorization failed.", flash[:alert]
    assert_not Profile.instance.strava_connected?
  end

  test "the callback stores the granted scope" do
    state = start["state"]
    stub_request(:post, TOKEN_URL).to_return(body: {access_token: "a", refresh_token: "r", expires_at: 6.hours.from_now.to_i}.to_json)

    get strava_callback_path(code: "c", state:, scope: "read,activity:read_all,profile:read_all")

    assert_equal "read,activity:read_all,profile:read_all", Profile.instance.strava_scope
    assert Profile.instance.strava_gear_access?
  end

  test "the nav button is Connect, Reconnect or absent by connection and scope" do
    get root_path
    follow_redirect!
    assert_select "form[action=?][data-turbo=false] button", strava_connection_path, text: "Connect Strava"

    Profile.instance.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    Profile.instance.update!(strava_scope: "read,activity:read_all")
    get "/overview"
    assert_select "form[action=?][data-turbo=false] button", strava_connection_path, text: "Reconnect Strava"

    Profile.instance.update!(strava_scope: "read,activity:read_all,profile:read_all")
    get "/overview"
    assert_select "form[action=?]", strava_connection_path, false
  end

  private
  def with_env(vars)
    old = vars.keys.index_with { ENV[it] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| ENV[key] = value }
  end
end
