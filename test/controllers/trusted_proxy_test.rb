require "test_helper"

class TrustedProxyTest < ActionDispatch::IntegrationTest
  CADDY = {"REMOTE_ADDR" => "100.101.102.103", "HTTP_HOST" => "chartlek.rekar.eu", "HTTP_X_FORWARDED_PROTO" => "https", "HTTP_X_FORWARDED_FOR" => "192.168.1.20"}

  def redirect_uri(headers)
    post(strava_connection_path, headers:)

    URI.decode_www_form(URI(response.location).query).to_h["redirect_uri"]
  end

  test "the Strava callback is https at the public host behind the tailnet proxy" do
    assert_equal "https://chartlek.rekar.eu/strava/callback", redirect_uri(CADDY)
  end

  test "the client address comes from the forwarded header when the proxy is on the tailnet" do
    get "/up", headers: CADDY

    assert_equal "192.168.1.20", request.remote_ip
  end

  test "the forwarded client address is ignored from a proxy outside the trusted ranges" do
    get "/up", headers: CADDY.merge("REMOTE_ADDR" => "203.0.113.9")

    assert_equal "203.0.113.9", request.remote_ip
  end

  test "the default private ranges stay trusted" do
    assert_equal "https://chartlek.rekar.eu/strava/callback", redirect_uri(CADDY.merge("REMOTE_ADDR" => "172.18.0.1"))
  end

  test "a direct LAN request stays plain http" do
    assert_equal "http://192.168.1.50:9295/strava/callback", redirect_uri({"REMOTE_ADDR" => "192.168.1.20", "HTTP_HOST" => "192.168.1.50:9295"})
  end
end
