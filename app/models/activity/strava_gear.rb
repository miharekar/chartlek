module Activity::StravaGear
  extend ActiveSupport::Concern

  GEAR_WINDOW = 30.days

  class_methods do
    def sync_strava_gear_later(full: false)
      Activity::StravaGearJob.perform_later(full:)
    end

    def sync_strava_gear_now(full: false, client: Strava::Client.new, summaries: nil)
      profile = Profile.instance

      if profile.strava_gear_access?
        summaries ||= client.activities(after: full ? nil : GEAR_WINDOW.ago.to_i)
        read_strava_gear_ids(summaries)
        Gear.sync(strava_gear_ids(full, client), client:, force: full)
        profile.update!(strava_gear_synced_at: Time.current) if full
      end
    end

    def read_strava_gear_ids(summaries)
      summaries.select { it.key?("gear_id") }.group_by { it["gear_id"] }.each do |gear_id, group|
        where(strava_id: group.pluck("id")).where("strava_gear_id IS NOT ?", gear_id).find_each { it.update!(strava_gear_id: gear_id) }
      end
    end

    private
    def strava_gear_ids(full, client)
      ids = where.not(strava_gear_id: nil).distinct.pluck(:strava_gear_id)

      full ? ids | client.athlete.fetch("shoes", []).pluck("id") : ids
    end
  end
end
