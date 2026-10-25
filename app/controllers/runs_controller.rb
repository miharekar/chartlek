class RunsController < ApplicationController
  def index
    @year = selected_year
    @month = params[:month].to_i.presence_in(1..12) if @year
    @runs = Activity.listed(year: @year, month: @month, sort: params[:sort], dir: params[:dir]).to_a
  end

  def show
    @run = Activity.find(params.expect(:id))
  end

  private
  def selected_year
    if params[:year] == "all"
      nil
    else
      params[:year].to_i.nonzero? || Activity.today.year
    end
  end
end
