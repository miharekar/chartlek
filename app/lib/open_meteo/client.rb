require "net/http"

class OpenMeteo::Client
  class Error < StandardError; end

  ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
  HOURLY = "temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,weather_code"
  DAILY = "sunrise,sunset"
  MIN_INTERVAL = 1.0
  MAX_ATTEMPTS = 5
  TRANSIENT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, OpenSSL::SSL::SSLError, SocketError]

  class_attribute :sleeper, default: ->(seconds) { sleep(seconds) }

  def weather(lat:, lng:, date:)
    uri = URI(ARCHIVE_URL)
    uri.query = URI.encode_www_form(
      latitude: lat.round(2), longitude: lng.round(2),
      start_date: date.iso8601, end_date: date.iso8601,
      hourly: HOURLY, daily: DAILY, timezone: "auto", wind_speed_unit: "kmh"
    )
    response = request(uri)

    raise Error, "Open-Meteo responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private
  def request(uri)
    attempts = 0

    loop do
      attempts += 1
      response = begin
        throttled { perform(uri) }
      rescue *TRANSIENT_ERRORS
        raise if attempts >= MAX_ATTEMPTS
      end

      return response if response && !(retryable?(response) && attempts < MAX_ATTEMPTS)

      sleeper.call(2**attempts)
    end
  end

  def retryable?(response)
    response.code == "429" || response.code.start_with?("5")
  end

  def throttled
    if @last_request_at
      wait = MIN_INTERVAL - (monotonic_now - @last_request_at)
      sleeper.call(wait) if wait > 0
    end

    @last_request_at = monotonic_now
    yield
  end

  def perform(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 60
    http.request(Net::HTTP::Get.new(uri))
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
