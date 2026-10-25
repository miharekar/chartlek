require "net/http"

class Strava::Client
  class Error < StandardError; end

  AUTHORIZE_URL = "https://www.strava.com/oauth/authorize"
  TOKEN_URL = "https://www.strava.com/oauth/token"
  ACTIVITIES_URL = "https://www.strava.com/api/v3/athlete/activities"
  SCOPE = "activity:read_all"
  PER_PAGE = 200

  def initialize(client_id: ENV["STRAVA_CLIENT_ID"], client_secret: ENV["STRAVA_SECRET"])
    @client_id = client_id
    @client_secret = client_secret
  end

  def authorize_url(redirect_uri, state:)
    "#{AUTHORIZE_URL}?#{URI.encode_www_form(client_id: @client_id, redirect_uri:, response_type: "code", approval_prompt: "auto", scope: SCOPE, state:)}"
  end

  def authorize(code)
    response = Net::HTTP.post_form(URI(TOKEN_URL), client_id: @client_id, client_secret: @client_secret, code:, grant_type: "authorization_code")
    @access_token = JSON.parse(checked(response, "token exchange").body).fetch("access_token")
  end

  def activities
    (1..).lazy.map { activities_page(it) }.take_while(&:any?).to_a.flatten(1)
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private
  def activities_page(page)
    uri = URI(ACTIVITIES_URL)
    uri.query = URI.encode_www_form(page:, per_page: PER_PAGE)

    JSON.parse(checked(Net::HTTP.get_response(uri, "Authorization" => "Bearer #{@access_token}"), "activities page #{page}").body)
  end

  def checked(response, label)
    raise Error, "Strava #{label} responded #{response.code}: #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

    response
  end
end
