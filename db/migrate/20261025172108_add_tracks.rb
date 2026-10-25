class AddTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :tracks do |t|
      t.references :activity, null: false, foreign_key: true, index: {unique: true}
      t.json :data, null: false

      t.timestamps
    end

    add_column :activities, :splits, :json
    add_column :activities, :pace_profile, :json
    add_column :activities, :pace_variability, :float
  end
end
