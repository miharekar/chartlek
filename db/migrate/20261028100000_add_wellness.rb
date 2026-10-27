class AddWellness < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :hr_zones, :json
    add_column :profiles, :wellness_synced_at, :datetime

    create_table :wellness_days do |t|
      t.date :date, null: false
      t.integer :resting_hr
      t.integer :resting_hr_avg_7d
      t.integer :hrv_last_night
      t.integer :hrv_weekly_avg
      t.integer :hrv_baseline_low
      t.integer :hrv_baseline_high
      t.string :hrv_status
      t.integer :body_battery_high
      t.integer :body_battery_low
      t.integer :body_battery_wake
      t.integer :stress_avg
      t.float :weight_kg
      t.json :raw, null: false, default: {}
      t.timestamps
      t.index :date, unique: true
    end
  end
end
