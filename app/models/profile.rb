class Profile < ApplicationRecord
  SYNC_STALE_AFTER = 15.minutes
  SYNC_INTERVAL = 30.minutes
  INVALID_KEY_ERROR = "Garmin key is invalid or expired"

  encrypts :strava_access_token, :strava_refresh_token

  def self.instance
    first_or_create!
  end

  def start_sync
    with_lock do
      if syncing?
        false
      else
        @resuming_sync = sync_error.present? || sync_started_at.present?
        update!(sync_started_at: Time.current, sync_error: nil)
        true
      end
    end
  end

  def resuming_sync?
    @resuming_sync.present?
  end

  def sync_progress
    update!(sync_started_at: Time.current)
  end

  def finish_sync(error: nil)
    if error
      update!(sync_started_at: nil, sync_error: error)
    else
      update!(sync_started_at: nil, synced_at: Time.current, sync_error: nil)
    end
  end

  def syncing?
    sync_started_at.present? && sync_started_at > SYNC_STALE_AFTER.ago
  end

  def sync_due?
    last_attempted_at = sync_started_at || (sync_error.present? ? updated_at : synced_at)

    !syncing? && (last_attempted_at.nil? || last_attempted_at < SYNC_INTERVAL.ago)
  end

  def strava_connected?
    strava_refresh_token.present?
  end

  def store_strava_tokens(access_token:, refresh_token:, expires_at:)
    update!(strava_access_token: access_token, strava_refresh_token: refresh_token, strava_token_expires_at: Time.zone.at(expires_at))
  end

  def disconnect_strava
    update!(strava_access_token: nil, strava_refresh_token: nil, strava_token_expires_at: nil)
  end

  def invalid_key?
    sync_error == INVALID_KEY_ERROR
  end
end
