class AddStravaConnection < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :strava_access_token, :text
    add_column :profiles, :strava_refresh_token, :text
    add_column :profiles, :strava_token_expires_at, :datetime
    add_column :activities, :strava_id, :bigint
    add_index :activities, :strava_id

    reversible do |direction|
      direction.up { execute "UPDATE activities SET strava_id = CAST(external_id AS INTEGER) WHERE source = 'strava'" }
    end
  end
end
