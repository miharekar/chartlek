class WellnessesController < ApplicationController
  def show
    @trends = Wellness::Trends.new(from: params[:from], to: params[:to])
  end
end
