class Activity < ApplicationRecord
  include GarminSync, StravaImport

  def self.today
    newest = order(:started_at).last
    offset = newest ? newest.local_started_at - newest.started_at : 0

    (Time.current + offset).to_date
  end

  validates :external_id, :started_at, :local_started_at, :activity_type, :distance_m, :timer_s, presence: true
  validates :source, inclusion: {in: %w[garmin strava]}
  validates :external_id, uniqueness: {scope: :source}

  def external_url
    if source == "garmin"
      "https://connect.garmin.com/app/activity/#{external_id}"
    else
      "https://www.strava.com/activities/#{external_id}"
    end
  end
end
