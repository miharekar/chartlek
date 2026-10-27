module Activity::StravaGear
  extend ActiveSupport::Concern

  GEAR_WINDOW = 30.days
  SUGGESTION_WINDOW = 14.days

  included do
    belongs_to :gear, foreign_key: :strava_gear_id, primary_key: :strava_id, optional: true, inverse_of: false
  end

  class_methods do
    def gear_unset
      where.not(strava_id: nil).where(strava_gear_id: nil)
    end

    def with_gear(gear)
      if gear == "none"
        gear_unset
      elsif gear.present?
        where(strava_gear_id: gear)
      else
        all
      end
    end

    def suggested_gear(runs)
      window = SUGGESTION_WINDOW.to_i
      used = unscoped.where.not(strava_gear_id: nil).order(:local_started_at).pluck(:local_started_at, :strava_gear_id).map { [it[0].to_i, it[1]] }
      times = used.map(&:first)
      ids = runs.to_h do |run|
        at = run.local_started_at.to_i
        nearby = used[(times.bsearch_index { it >= at - window } || used.size)...(times.bsearch_index { it > at + window } || used.size)]

        [run.id, nearby.sort_by { (it[0] - at).abs }.map(&:last).tally.max_by(&:last)&.first]
      end
      gears = Gear.where(strava_id: ids.values.compact.uniq).index_by(&:strava_id)

      ids.transform_values { gears[it] || (Gear.new(strava_id: it) if it) }
    end

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

    def sync_strava_gear_after_link(full:, client:, summaries:)
      profile = Profile.instance

      if profile.strava_gear_access?
        everything = full || profile.strava_gear_synced_at.nil?
        sync_strava_gear_now(full: everything, client:, summaries: (summaries if full))
      end
    rescue Strava::Client::NotConnected
      raise
    rescue Strava::Client::Error => error
      Rails.logger.warn("Strava gear pass skipped: #{error.class}")
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
