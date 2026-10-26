class StravaConnectionsController < ApplicationController
  def show
    state = session.delete(:strava_state)

    if params[:error].present?
      redirect_to root_path, alert: "Strava connection was cancelled."
    elsif params[:code].present? && state.present? && ActiveSupport::SecurityUtils.secure_compare(state, params[:state].to_s)
      connect(params[:code], params[:scope].to_s)
    else
      redirect_to root_path, alert: "Strava authorization failed: state mismatch."
    end
  end

  def create
    session[:strava_state] = SecureRandom.hex(16)

    redirect_to Strava::Client.new.authorize_url(strava_callback_url, state: session[:strava_state]), allow_other_host: true
  end

  private
  def connect(code, scope)
    Strava::Client.new.authorize(code)
    Activity.link_strava_later(full: true)
    notice = "Strava connected. Linking your runs."
    notice += " Private activities were not shared, so they are skipped." unless scope.split(",").include?(Strava::Client::SCOPE)

    redirect_to root_path, notice:
  rescue Strava::Client::Error
    redirect_to root_path, alert: "Strava authorization failed."
  end
end
