class AddChartMetricsToTracks < ActiveRecord::Migration[8.1]
  def change
    add_column :tracks, :chart_metrics, :json
  end
end
