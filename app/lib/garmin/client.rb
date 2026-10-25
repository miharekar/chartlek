require "net/http"

class Garmin::Client
  class Error < StandardError; end
  class InvalidKey < Error; end

  BASE_URL = "https://personal.connectapi.garmin.com"
  TOKEN_PATH = "/personalapitoken-service/personal-api/personal-api-key/token"
  ACTIVITIES_PATH = "/activitylist-service/activities/search/activities"
  SETTINGS_PATH = "/userprofile-service/userprofile/settings"
  DOWNLOAD_PATH = "/download-service/files/activity"
  MIN_INTERVAL = 1.0
  MAX_ATTEMPTS = 5
  TOKEN_MARGIN = 1.hour
  TRANSIENT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, OpenSSL::SSL::SSLError, SocketError]

  class_attribute :sleeper, default: ->(seconds) { sleep(seconds) }

  attr_reader :request_count

  def initialize(key: ENV["GARMIN_API_TOKEN"])
    @key = key
    @request_count = 0
  end

  def activities(start:, limit:, activity_type: "running")
    get(ACTIVITIES_PATH, activityType: activity_type, start:, limit:)
  end

  def profile_settings
    get(SETTINGS_PATH)
  end

  def download(activity_id)
    authorized_response(URI("#{BASE_URL}#{DOWNLOAD_PATH}/#{activity_id}")).body
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private
  def get(path, **params)
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params) if params.any?

    JSON.parse(authorized_response(uri).body)
  end

  def authorized_response(uri)
    response = request(Net::HTTP::Get, uri, "Authorization" => "Bearer #{token}")

    if response.code == "401"
      forget_token
      response = request(Net::HTTP::Get, uri, "Authorization" => "Bearer #{token}")
    end

    raise Error, "Garmin API responded #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)

    response
  end

  def token
    Rails.cache.read(token_cache_key) || fresh_token
  end

  def fresh_token
    token = exchange_key
    ttl = token_expiry(token) - TOKEN_MARGIN - Time.current
    Rails.cache.write(token_cache_key, token, expires_in: ttl) if ttl > 0
    token
  end

  def token_expiry(token)
    claims = JSON.parse(token.split(".")[1].to_s.tr("-_", "+/").unpack1("m"))
    Time.zone.at(claims["exp"])
  rescue JSON::ParserError, TypeError
    Time.current
  end

  def exchange_key
    response = request(Net::HTTP::Post, URI("#{BASE_URL}#{TOKEN_PATH}"), "Authorization" => "ApiKey #{@key}")

    if %w[401 403].include?(response.code)
      raise InvalidKey, "Garmin rejected the API key"
    elsif !response.is_a?(Net::HTTPSuccess)
      raise Error, "Garmin token exchange responded #{response.code}"
    end

    response.body.strip
  end

  def forget_token
    Rails.cache.delete(token_cache_key)
  end

  def token_cache_key
    "garmin/token/#{Digest::SHA256.hexdigest(@key.to_s)[0, 12]}"
  end

  def request(klass, uri, headers)
    attempts = 0

    loop do
      attempts += 1
      response = begin
        throttled { perform(klass, uri, headers) }
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
    @request_count += 1
    yield
  end

  def perform(klass, uri, headers)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 60
    http.request(klass.new(uri, headers))
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
