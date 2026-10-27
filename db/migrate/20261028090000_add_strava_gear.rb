class AddStravaGear < ActiveRecord::Migration[8.1]
  def change
    create_table :gears do |t|
      t.string :strava_id, null: false
      t.string :name
      t.string :brand_name
      t.string :model
      t.boolean :retired, null: false, default: false
      t.json :summary
      t.datetime :synced_at
      t.timestamps
    end
    add_index :gears, :strava_id, unique: true

    add_column :activities, :strava_gear_id, :string
    add_index :activities, :strava_gear_id
    add_column :profiles, :strava_scope, :string
    add_column :profiles, :strava_gear_synced_at, :datetime
  end
end
