class OverviewsController < ApplicationController
  def show
    @overview = Overview.for(year: request.path_parameters[:year]&.to_i, month: request.path_parameters[:month]&.to_i)
  end
end
