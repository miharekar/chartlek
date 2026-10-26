class RemoveSpiFromActivities < ActiveRecord::Migration[8.1]
  def change
    remove_column :activities, :spi, :float
  end
end
