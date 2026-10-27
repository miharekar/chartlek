class GearsController < ApplicationController
  def index
    @profile = sync_profile
    @ready = @profile.strava_gear_ready?

    if @ready
      @usage = Gear.usage
      @unset = Gear.unset_usage
      @chart = Gear.monthly(@usage)
    end
  end
end
