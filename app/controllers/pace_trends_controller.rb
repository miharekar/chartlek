class PaceTrendsController < ApplicationController
  def show
    @pace_trend = PaceTrend.new(exclude_paused: params[:no_pauses] == "1", races_only: params[:races] == "1", from: params[:from], to: params[:to], distance: params[:distance])
  end
end
