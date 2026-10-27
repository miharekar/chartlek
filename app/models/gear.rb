class Gear < ApplicationRecord
  STALE_AFTER = 1.week

  validates :strava_id, presence: true

  def self.sync(ids, client:, force: false)
    ids.each do |id|
      gear = find_by(strava_id: id)
      fetch(id, client:) if force || gear.nil? || gear.stale?
    end
  end

  def self.fetch(id, client:)
    payload = client.gear(id)
    gear = create_or_find_by!(strava_id: id)

    if payload
      gear.update!(name: payload["name"], brand_name: payload["brand_name"], model: payload["model_name"], retired: payload["retired"] == true, summary: payload, synced_at: Time.current)
    else
      gear.update!(synced_at: Time.current)
    end
  end

  def stale?
    synced_at.nil? || synced_at < STALE_AFTER.ago
  end
end
