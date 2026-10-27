class AddStravaGearAttemptsToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :strava_gear_attempts, :integer, null: false, default: 0
  end
end
