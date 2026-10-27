class CreateGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :goals do |t|
      t.string :period, null: false
      t.date :starts_on, null: false
      t.float :distance_m, null: false
      t.timestamps
    end

    add_index :goals, %i[period starts_on], unique: true
  end
end
