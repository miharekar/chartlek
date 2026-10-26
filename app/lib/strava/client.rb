require "net/http"

class Strava::Client
  class Error < StandardError; end
  class NotConnected < Error; end

  AUTHORIZE_URL = "https://www.strava.com/oauth/authorize"
  TOKEN_URL = "https://www.strava.com/oauth/token"
  ACTIVITIES_URL = "https://www.strava.com/api/v3/athlete/activities"
  SCOPE = "activity:read_all"
  PER_PAGE = 200
  REFRESH_MARGIN = 5.minutes

  def initialize(client_id: ENV["STRAVA_CLIENT_ID"], client_secret: ENV["STRAVA_SECRET"], profile: Profile.instance)
    @client_id = client_id
    @client_secret = client_secret
    @profile = profile
  end

  def authorize_url(redirect_uri, state:)
    "#{AUTHORIZE_URL}?#{URI.encode_www_form(client_id: @client_id, redirect_uri:, response_type: "code", approval_prompt: "auto", scope: SCOPE, state:)}"
  end

  def authorize(code)
    store(request_token(grant_type: "authorization_code", code:, label: "token exchange"))
  end

  def activities(after: nil)
    (1..).lazy.map { activities_page(it, after) }.take_while(&:any?).to_a.flatten(1)
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private
  def activities_page(page, after)
    uri = URI(ACTIVITIES_URL)
    uri.query = URI.encode_www_form({page:, per_page: PER_PAGE, after:}.compact)
    response = Net::HTTP.get_response(uri, "Authorization" => "Bearer #{access_token}")

    if response.code == "401"
      @profile.disconnect_strava
      raise NotConnected, "Strava rejected the access token"
    else
      JSON.parse(checked(response, "activities page #{page}").body)
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
    @profile.with_lock do
      raise NotConnected, "Strava is not connected" unless @profile.strava_connected?

      store(request_token(grant_type: "refresh_token", refresh_token: @profile.strava_refresh_token, label: "token refresh")) if expiring?
    end
  rescue NotConnected
    raise
  rescue Error => error
    if error.message.match?(/responded (400|401)/)
      @profile.disconnect_strava
      raise NotConnected, "Strava revoked the connection"
    else
      raise
    end
  end

  def request_token(label:, **params)
    response = Net::HTTP.post_form(URI(TOKEN_URL), client_id: @client_id, client_secret: @client_secret, **params)

    JSON.parse(checked(response, label).body)
  end

  def store(token)
    @profile.store_strava_tokens(access_token: token.fetch("access_token"), refresh_token: token.fetch("refresh_token"), expires_at: token.fetch("expires_at"))
  end

  def checked(response, label)
    raise Error, "Strava #{label} responded #{response.code}: #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

    response
  end
end
