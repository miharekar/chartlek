require "socket"
require "io/wait"

class Strava::Callback
  class Timeout < StandardError; end

  PATH = "/strava/callback"
  PAGE = "<!DOCTYPE html><title>Smashback</title><p>Strava authorization received. You can close this tab.</p>"

  def initialize(port: 8137)
    @server = TCPServer.new("127.0.0.1", port)
  end

  def redirect_uri
    "http://127.0.0.1:#{@server.addr[1]}#{PATH}"
  end

  def wait(timeout: 600)
    deadline = monotonic_now + timeout

    loop do
      ready = IO.select([@server], nil, nil, [deadline - monotonic_now, 0].max)
      raise Timeout, "No Strava authorization within #{timeout} seconds" unless ready

      params = receive(@server.accept)
      return params if params
    end
  ensure
    @server.close
  end

  private
  def receive(connection)
    line = connection.gets if connection.wait_readable(5)
    uri = URI(line.to_s.split[1].to_s)

    if uri.path == PATH
      URI.decode_www_form(uri.query.to_s).to_h.tap { respond(connection, "200 OK", PAGE) }
    else
      respond(connection, "404 Not Found", "Not found")
      nil
    end
  rescue URI::InvalidURIError, SystemCallError
    nil
  ensure
    connection.close
  end

  def respond(connection, status, body)
    connection.write("HTTP/1.1 #{status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  rescue SystemCallError
    nil
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
