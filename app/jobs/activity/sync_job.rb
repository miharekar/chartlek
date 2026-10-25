class Activity::SyncJob < ApplicationJob
  def perform
    Activity.sync_now
  end
end
