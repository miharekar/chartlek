class RemovePaceProfileFromActivities < ActiveRecord::Migration[8.1]
  def change
    remove_column :activities, :pace_profile, :json
  end
end
