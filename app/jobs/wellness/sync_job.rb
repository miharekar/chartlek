class Wellness::SyncJob < ApplicationJob
  def perform
    Wellness::Sync.new.refresh
  end
end
