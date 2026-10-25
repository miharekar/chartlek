class SyncsController < ApplicationController
  def create
    Activity.sync_later
    redirect_back_or_to "/overview"
  end
end
