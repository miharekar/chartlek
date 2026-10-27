class GearSyncsController < ApplicationController
  def create
    if sync_profile.strava_gear_access?
      Activity.sync_strava_gear_later(full: true)
      redirect_back_or_to gears_path, notice: "Gear scan started. Reload in a minute."
    else
      redirect_back_or_to gears_path, alert: "Reconnect Strava first: gear needs profile access."
    end
  end
end
