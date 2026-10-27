class AddBandsToActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :bands, :json
  end
end
