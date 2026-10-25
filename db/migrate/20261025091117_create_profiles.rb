class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.json :settings
      t.datetime :synced_at
      t.datetime :sync_started_at
      t.text :sync_error

      t.timestamps
    end
  end
end
