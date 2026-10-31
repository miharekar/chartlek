require "net/http"

class Strava::Client
  class Error < StandardError; end
  class NotConnected < Error; end

  AUTHORIZE_URL = "https://www.strava.com/oauth/authorize"
  TOKEN_URL = "https://www.strava.com/oauth/token"
  API_URL = "https://www.strava.com/api/v3"
  ACTIVITIES_URL = "#{API_URL}/athlete/activities"
  PUSH_URL = "#{API_URL}/push_subscriptions"
  PRIVATE_SCOPE = "activity:read_all"
  GEAR_SCOPE = "profile:read_all"
  SCOPE = "#{PRIVATE_SCOPE},#{GEAR_SCOPE}"
  ACTIVITY_SCOPES = %w[activity:read activity:read_all].freeze
  PER_PAGE = 200
  REFRESH_MARGIN = 5.minutes
  TIMEOUT = 10

  def initialize(client_id: ENV["STRAVA_CLIENT_ID"], client_secret: ENV["STRAVA_SECRET"], profile: Profile.instance)
    @client_id = client_id
    @client_secret = client_secret
    @profile = profile
  end

  def authorize_url(redirect_uri, state:)
    "#{AUTHORIZE_URL}?#{URI.encode_www_form(client_id: @client_id, redirect_uri:, response_type: "code", approval_prompt: "auto", scope: SCOPE, state:)}"
  end

  def authorize(code, scope:)
    store(request_token(grant_type: "authorization_code", code:, label: "token exchange"))
    @profile.update!(strava_scope: scope)
  end

  def activities(after: nil)
    (1..).lazy.map { activities_page(it, after) }.take_while(&:any?).to_a.flatten(1)
  end

  def athlete
    JSON.parse(checked(get(URI("#{API_URL}/athlete")), "athlete").body)
  end

  def gear(id)
    response = get(URI("#{API_URL}/gear/#{ERB::Util.url_encode(id)}"))

    JSON.parse(checked(response, "gear").body) unless response.code == "404"
  end

  def subscriptions
    JSON.parse(checked(push_request(:get), "push subscriptions").body)
  end

  def subscribe(callback_url:, verify_token:)
    response = push_request(:post, callback_url:, verify_token:)

    JSON.parse(checked(response, "push subscription", redact: [callback_url, verify_token]).body)
  end

  def unsubscribe(id)
    checked(push_request(:delete, id:), "push subscription removal")
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private
  def activities_page(page, after)
    uri = URI(ACTIVITIES_URL)
    uri.query = URI.encode_www_form({page:, per_page: PER_PAGE, after:}.compact)

    JSON.parse(checked(get(uri), "activities page #{page}").body)
  end

  def get(uri)
    response = start(uri) { it.get(uri.request_uri, "Authorization" => "Bearer #{access_token}") }

    if response.code == "401"
      @profile.disconnect_strava
      raise NotConnected, "Strava rejected the access token"
    else
      response
    end
  end

  def access_token
    raise NotConnected, "Strava is not connected" unless @profile.strava_connected?

    refresh if expiring?
    @profile.strava_access_token
  end

  def expiring?
    @profile.strava_token_expires_at.nil? || @profile.strava_token_expires_at < REFRESH_MARGIN.from_now
  end

  def refresh
    @profile.reload
    raise NotConnected, "Strava is not connected" unless @profile.strava_connected?

    if expiring?
      sent = @profile.strava_refresh_token

      begin
        store(request_token(grant_type: "refresh_token", refresh_token: sent, label: "token refresh"))
      rescue Error => error
        rejected(error, sent)
      end
    end
  end

  def rejected(error, sent)
    raise error unless error.message.match?(/responded (400|401)/)

    @profile.reload
    if @profile.strava_refresh_token == sent
      @profile.disconnect_strava
      raise NotConnected, "Strava revoked the connection"
    elsif !@profile.strava_connected?
      raise NotConnected, "Strava is not connected"
    end
  end

  def request_token(label:, **params)
    uri = URI(TOKEN_URL)
    response = start(uri) { it.post(uri.path, URI.encode_www_form(client_id: @client_id, client_secret: @client_secret, **params), "Content-Type" => "application/x-www-form-urlencoded") }

    JSON.parse(checked(response, label).body)
  end

  def push_request(verb, id: nil, **params)
    uri = URI([PUSH_URL, id && Integer(id)].compact.join("/"))
    credentials = {client_id: @client_id, client_secret: @client_secret}

    case verb
    when :post
      start(uri) { it.post(uri.path, URI.encode_www_form(credentials.merge(params)), "Content-Type" => "application/x-www-form-urlencoded") }
    else
      uri.query = URI.encode_www_form(credentials)
      start(uri) { it.public_send(verb, uri.request_uri) }
    end
  end

  def start(uri, &)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT, &)
  end

  def store(token)
    @profile.store_strava_tokens(access_token: token.fetch("access_token"), refresh_token: token.fetch("refresh_token"), expires_at: token.fetch("expires_at"))
  end

  def checked(response, label, redact: [])
    unless response.is_a?(Net::HTTPSuccess)
      body = redact.reduce(response.body.to_s) { |text, secret| text.gsub(secret, "[filtered]") }
      raise Error, "Strava #{label} responded #{response.code}: #{body.truncate(200)}"
    end

    response
  end
end
