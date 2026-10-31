class StravaWebhookGate
  HOST = "chartlek-hooks.rekar.eu"
  FLAG = "chartlek.strava_webhook"
  NOT_FOUND = [404, {"content-type" => "text/plain", "content-length" => "0"}, []].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    if webhook?(env["PATH_INFO"].to_s)
      admit(env)
      @app.call(env)
    elsif public?(env)
      NOT_FOUND.dup
    else
      @app.call(env)
    end
  end

  private
  def webhook?(path)
    token = Strava::Webhook.token

    token.present? && ActiveSupport::SecurityUtils.secure_compare(path, "#{Strava::Webhook::PATH}/#{token}")
  end

  def admit(env)
    query = env["QUERY_STRING"].to_s
    fullpath = query.empty? ? Strava::Webhook::PATH : "#{Strava::Webhook::PATH}?#{query}"

    env[FLAG] = true
    env["PATH_INFO"] = Strava::Webhook::PATH
    env["ORIGINAL_FULLPATH"] = fullpath
    env["REQUEST_URI"] = fullpath if env.key?("REQUEST_URI")
    env["REQUEST_PATH"] = Strava::Webhook::PATH if env.key?("REQUEST_PATH")
  end

  def public?(env)
    env["HTTP_CF_RAY"].present? || env["HTTP_HOST"].to_s.downcase.sub(/:\d+\z/, "").chomp(".") == HOST
  end
end
