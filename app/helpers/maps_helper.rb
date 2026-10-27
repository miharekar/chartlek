module MapsHelper
  METRICS = {"pace" => "Pace", "hr" => "HR", "grade" => "Grade", "cadence" => "Cadence"}.freeze

  def mapbox_token
    token = ENV["MAPBOX_TOKEN"].to_s
    token if token.start_with?("pk.")
  end

  def pro_map_metrics(run, track, zones)
    present = {"pace" => run.splits.present?, "hr" => zones.present?, "grade" => track.data.key?("alt"), "cadence" => track.data.key?("cad")}

    METRICS.select { |key, _| present[key] }
  end

  def pro_map_splits(run)
    start = 0.0

    run.splits.map do |split|
      from = start
      start += split["distance"]
      split.merge("from" => from, "to" => start)
    end
  end

  def pro_map_gain(split)
    "+#{split["gain"].round} / −#{split["loss"].round} m" if split["gain"]
  end
end
