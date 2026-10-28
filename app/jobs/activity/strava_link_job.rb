class Activity::StravaLinkJob < ApplicationJob
  def perform(full: false)
    before = strava_state
    Activity.link_strava_now(full:)
  rescue Strava::Client::NotConnected
    nil
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to(:garmin_sync) if strava_state != before
  end

  private
  def strava_state
    [
      Activity.where.not(strava_id: nil).order(:id).pluck(:id, :strava_id, :strava_gear_id),
      Gear.count,
      Gear.maximum(:updated_at),
      Profile.instance.strava_gear_synced_at
    ]
  end
end
