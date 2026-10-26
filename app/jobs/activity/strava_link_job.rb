class Activity::StravaLinkJob < ApplicationJob
  def perform(full: false)
    Activity.link_strava_now(full:)
  rescue Strava::Client::NotConnected
    nil
  end
end
