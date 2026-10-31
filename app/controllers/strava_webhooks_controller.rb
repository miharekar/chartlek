class StravaWebhooksController < ApplicationController
  before_action :require_gate
  skip_forgery_protection only: :create

  def show
    if params["hub.mode"] == "subscribe" && verified?
      render json: {"hub.challenge" => params["hub.challenge"].to_s}
    else
      head :not_found
    end
  end

  def create
    event = request.request_parameters
    Activity.handle_strava_event(object_type: event["object_type"], aspect_type: event["aspect_type"], object_id: event["object_id"], updates: event["updates"])

    head :ok
  end

  private
  def require_gate
    head :not_found unless request.env[StravaWebhookGate::FLAG]
  end

  def verified?
    token = Strava::Webhook.verify_token

    token.present? && ActiveSupport::SecurityUtils.secure_compare(params["hub.verify_token"].to_s, token)
  end
end
