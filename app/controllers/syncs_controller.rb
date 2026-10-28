class SyncsController < ApplicationController
  def create
    Activity.sync_later

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("sync_status", partial: "syncs/status", locals: {profile: Profile.instance, queued: true}) }
      format.html { redirect_back_or_to "/overview" }
    end
  end
end
