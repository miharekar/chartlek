require "test_helper"

class Strava::CallbackTest < ActiveSupport::TestCase
  test "returns the authorization params and answers other requests with 404" do
    callback = Strava::Callback.new(port: 0)
    port = URI(callback.redirect_uri).port
    waiter = Thread.new { callback.wait(timeout: 5) }

    assert_match "404 Not Found", raw_get(port, "/favicon.ico")
    assert_match "200 OK", raw_get(port, "/strava/callback?state=abc&code=the-code&scope=read,activity:read_all")
    assert_equal({"state" => "abc", "code" => "the-code", "scope" => "read,activity:read_all"}, waiter.value)
  end

  test "ignores connections that send nothing" do
    callback = Strava::Callback.new(port: 0)
    port = URI(callback.redirect_uri).port
    waiter = Thread.new { callback.wait(timeout: 10) }

    TCPSocket.open("127.0.0.1", port).close
    raw_get(port, "/strava/callback?error=access_denied")

    assert_equal({"error" => "access_denied"}, waiter.value)
  end

  test "times out" do
    assert_raises(Strava::Callback::Timeout) { Strava::Callback.new(port: 0).wait(timeout: 0.1) }
  end

  private
  def raw_get(port, path)
    TCPSocket.open("127.0.0.1", port) do |socket|
      socket.write("GET #{path} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
      socket.read
    end
  end
end
