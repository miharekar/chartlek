class RunsController < ApplicationController
  def index
    @gear = params[:gear].presence if params[:gear].is_a?(String)
    @year = selected_year
    @month = params[:month].to_i.presence_in(1..12) if @year
    @runs = Activity.with_gear(@gear).listed(year: @year, month: @month, sort: params[:sort], dir: params[:dir]).includes(:gear).to_a
    @suggestions = Activity.suggested_gear(@runs) if @gear == "none"
    @filter_gear = Gear.find_by(strava_id: @gear) || Gear.new(strava_id: @gear) if @gear && @gear != "none"
  end

  def show
    @run = Activity.find(params.expect(:id))
  end

  private
  def selected_year
    if params[:year] == "all" || (@gear && params[:year].blank?)
      nil
    else
      params[:year].to_i.nonzero? || Activity.today.year
    end
  end
end
