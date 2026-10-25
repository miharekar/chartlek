class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.string :source, null: false
      t.string :external_id, null: false
      t.datetime :started_at, null: false
      t.datetime :local_started_at, null: false
      t.string :name
      t.string :activity_type, null: false
      t.boolean :indoor, null: false, default: false
      t.boolean :race, null: false, default: false
      t.float :distance_m, null: false
      t.float :timer_s, null: false
      t.float :moving_s
      t.float :elapsed_s
      t.float :elevation_gain_m
      t.float :elevation_loss_m
      t.integer :avg_hr
      t.integer :max_hr
      t.integer :calories
      t.float :avg_cadence
      t.float :max_cadence
      t.float :vo2max
      t.float :start_lat
      t.float :start_lng
      t.float :spi
      t.float :vdot
      t.string :location_name
      t.json :summary

      t.timestamps
    end

    add_index :activities, [ :source, :external_id ], unique: true
    add_index :activities, :local_started_at
  end
end
