module Activity::StravaLink
  extend ActiveSupport::Concern

  LINK_MARGIN = 10.minutes
  RECENT_WINDOW = 14.days

  included do
    before_save :own_strava_id, if: -> { source == "strava" && strava_id.nil? }
  end

  class_methods do
    def link_strava_later(full: false)
      Activity::StravaLinkJob.perform_later(full:)
    end

    def link_strava_now(full: false, client: Strava::Client.new)
      after = full ? nil : recent_strava_start

      if full || after
        summaries = client.activities(after: after&.to_i)
        link_strava_summaries(summaries)
      else
        0
      end
    end

    private
    def recent_strava_start
      oldest = where(strava_id: nil, started_at: RECENT_WINDOW.ago..).minimum(:started_at)

      oldest - LINK_MARGIN if oldest
    end

    def link_strava_summaries(summaries)
      api = Activity::StravaImport::Api.new(summaries)
      taken = where.not(strava_id: nil).pluck(:strava_id).to_set
      unlinked = where(strava_id: nil).order(:started_at).pluck(:id, :started_at)

      summaries.select { api.run?(it) && taken.exclude?(it["id"]) }.count do |summary|
        start = Time.iso8601(summary["start_date"])
        nearest = unlinked.select { (it[1] - start).abs <= LINK_MARGIN }.min_by { (it[1] - start).abs }

        if nearest && link_strava_run(nearest[0], summary["id"])
          unlinked.delete(nearest)
          true
        end
      end
    end

    def link_strava_run(id, strava_id)
      run = find(id)

      run.with_lock { run.update!(strava_id:) if run.strava_id.nil? }
    end
  end

  def strava_url
    "https://www.strava.com/activities/#{strava_id}" if strava_id
  end

  def garmin_url
    "https://connect.garmin.com/app/activity/#{external_id}" if source == "garmin"
  end

  private
  def own_strava_id
    self.strava_id = external_id.to_i if external_id.to_s.match?(/\A\d+\z/)
  end
end
