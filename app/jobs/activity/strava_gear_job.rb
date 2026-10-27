class Activity::StravaGearJob < ApplicationJob
  def perform(full: false)
    Activity.sync_strava_gear_now(full:)
  rescue Strava::Client::NotConnected
    nil
  end
end
