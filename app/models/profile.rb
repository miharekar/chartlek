class Profile < ApplicationRecord
  SYNC_STALE_AFTER = 15.minutes
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

  def strava_connected?
    strava_refresh_token.present?
  end

  def strava_gear_access?
    strava_connected? && strava_scope.to_s.split(",").include?(Strava::Client::GEAR_SCOPE)
  end

  def strava_gear_ready?
    strava_gear_access? && strava_gear_synced_at.present?
  end

  def strava_reconnect?
    strava_connected? && !strava_gear_access?
  end

  def store_strava_tokens(access_token:, refresh_token:, expires_at:)
    update!(strava_access_token: access_token, strava_refresh_token: refresh_token, strava_token_expires_at: Time.zone.at(expires_at))
  end

  def disconnect_strava
    update!(strava_access_token: nil, strava_refresh_token: nil, strava_token_expires_at: nil, strava_scope: nil)
  end

  def invalid_key?
    sync_error == INVALID_KEY_ERROR
  end
end
