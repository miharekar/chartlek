class TrainingBandsController < ApplicationController
  def show
    @bands = TrainingBands.new(from: params[:from], to: params[:to], category: params[:category], view: params[:view])
  end
end
