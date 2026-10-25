require "net/http"

class Smashrun::Client
  class Error < StandardError; end

  LOGIN_URL = "https://secure.smashrun.com/services/apiauth-jsonservice.asmx/ConnectUserLogin"
  BASE_URL = "https://api.smashrun.com/v1"
  MIN_INTERVAL = 15.0
  MAX_ATTEMPTS = 5
  TRANSIENT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, OpenSSL::SSL::SSLError, SocketError]

  class_attribute :sleeper, default: ->(seconds) { sleep(seconds) }

  def initialize(email: ENV["SMASHRUN_USERNAME"], password: ENV["SMASHRUN_PASSWORD"])
    @email = email
    @password = password
  end

  def activities
    JSON.parse(get("/my/activities"))
  end

  def activity(id)
    get("/my/activities/#{id}")
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private
  def get(path)
    uri = URI("#{BASE_URL}#{path}")
    response = api_request(uri)

    if response.code == "401"
      @token = nil
      response = api_request(uri)
    end

    raise Error, "Smashrun API responded #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def api_request(uri)
    request(Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{token}"), throttle: true)
  end

  def token
    @token ||= login
  end

  def login
    login_request = Net::HTTP::Post.new(URI(LOGIN_URL), "Content-Type" => "application/json; charset=utf-8")
    login_request.body = {loginEmail: @email, loginPassword: @password, clientId: "client", scopes: "read_activity", isToken: true}.to_json
    response = request(login_request, throttle: false)

    raise Error, "Smashrun login responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    access_token = parsed.dig("results", "auth", "access_token")

    raise Error, "Smashrun login failed (code #{parsed.dig("info", "failCode")})" if parsed.dig("info", "isFailed") || access_token.blank?

    access_token
  rescue JSON::ParserError
    raise Error, "Smashrun login returned an unreadable response"
  end

  def request(http_request, throttle:)
    attempts = 0

    loop do
      attempts += 1
      response = begin
        throttle ? throttled { perform(http_request) } : perform(http_request)
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

  def perform(http_request)
    uri = http_request.uri
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 300
    http.request(http_request)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
