module Activity::StravaWebhook
  extend ActiveSupport::Concern

  SYNC_DELAY = 1.minute

  class_methods do
    def handle_strava_event(object_type:, aspect_type:, object_id:, updates: nil)
      case [object_type, aspect_type]
      when %w[activity create]
        Activity::SyncJob.set(wait: SYNC_DELAY).perform_later
      when %w[activity delete]
        unlink_strava_activity(object_id)
      when %w[athlete update]
        disconnect_strava_athlete(updates)
      end
    end

    private
    def unlink_strava_activity(object_id)
      id = Integer(object_id, exception: false)

      if id
        unlinked = where.not(source: "strava").where(strava_id: id).update_all(strava_id: nil, strava_gear_id: nil)
        Turbo::StreamsChannel.broadcast_refresh_to(:garmin_sync) if unlinked.positive?
      end
    end

    def disconnect_strava_athlete(updates)
      if updates.is_a?(Hash) && updates["authorized"] == "false"
        Profile.instance.disconnect_strava
        Turbo::StreamsChannel.broadcast_refresh_to(:garmin_sync)
      end
    end
  end
end
