class AddWeatherToActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :weather, :json
  end
end
