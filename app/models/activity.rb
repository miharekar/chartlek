class Activity < ApplicationRecord
  include GarminSync, StravaImport, StravaLink, StravaGear, StravaWebhook, SmashrunImport, Performance, Physiology, HrZoning, Browsing, Weather, TrackProcessing

  has_one_attached :original, dependent: :purge
  has_one :track, dependent: :destroy

  def self.today
    newest = order(:started_at).last
    offset = newest ? newest.local_started_at - newest.started_at : 0

    (Time.current + offset).to_date
  end

  validates :external_id, :started_at, :local_started_at, :activity_type, :distance_m, :timer_s, presence: true
  validates :source, inclusion: {in: %w[garmin strava smashrun]}
  validates :external_id, uniqueness: {scope: :source}
end
