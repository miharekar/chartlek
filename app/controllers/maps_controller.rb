class MapsController < ApplicationController
  def show
    @run = Activity.find(params.expect(:run_id))
    @track = @run.track

    if @track&.mappable? && helpers.mapbox_token
      @zones = HrZones.current if @track.data.key?("hr")
    else
      redirect_to run_path(@run)
    end
  end
end
