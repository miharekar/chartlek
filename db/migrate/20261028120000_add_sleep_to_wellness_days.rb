class AddSleepToWellnessDays < ActiveRecord::Migration[8.1]
  def change
    change_table :wellness_days do |t|
      t.integer :sleep_s
      t.integer :sleep_deep_s
      t.integer :sleep_light_s
      t.integer :sleep_rem_s
      t.integer :sleep_awake_s
      t.integer :sleep_score
      t.float :sleep_hr_avg
      t.float :sleep_stress_avg
    end
  end
end
