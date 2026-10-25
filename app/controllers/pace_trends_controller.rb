class PaceTrendsController < ApplicationController
  def show
    @pace_trend = PaceTrend.new(metric: params[:metric], exclude_paused: params[:no_pauses] == "1", exclude_indoor: params[:no_indoor] == "1", races_only: params[:races] == "1", from: params[:from], to: params[:to], distance: params[:distance])
  end
end
