module Strava::Webhook
  PATH = "/strava/webhook"
  PATH_LABEL = "strava_webhook.path"
  VERIFY_LABEL = "strava_webhook.verify"

  def self.token(env = ENV)
    digest(PATH_LABEL, env)
  end

  def self.verify_token(env = ENV)
    digest(VERIFY_LABEL, env)
  end

  def self.callback_url(host, env = ENV)
    "https://#{host}#{PATH}/#{token(env)}"
  end

  def self.digest(label, env)
    secret = env["SECRET_KEY_BASE"]

    OpenSSL::HMAC.hexdigest("SHA256", secret, label) if secret.present?
  end
  private_class_method :digest
end
