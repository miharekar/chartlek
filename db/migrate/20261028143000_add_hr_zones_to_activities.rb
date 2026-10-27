class AddHrZonesToActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :hr_zones, :json
  end
end
