class Activity::StravaImport::Api
  TYPES = {"Run" => "running", "TrailRun" => "trail_running", "VirtualRun" => "virtual_run"}
  RACE_WORKOUT_TYPE = 1

  attr_reader :rows

  def initialize(summaries)
    @rows = summaries
  end

  def run?(summary)
    TYPES.key?(summary["sport_type"])
  end

  def attributes_for(summary)
    moving = summary["moving_time"]
    elapsed = summary["elapsed_time"]
    cadence = summary["average_cadence"]
    virtual = summary["sport_type"] == "VirtualRun"
    treadmill = summary["trainer"] == true && !virtual

    {
      source: "strava",
      external_id: summary["id"]&.to_s,
      started_at: parse_time(summary["start_date"]),
      local_started_at: parse_time(summary["start_date_local"]),
      name: summary["name"],
      activity_type: treadmill ? "treadmill_running" : TYPES[summary["sport_type"]],
      indoor: virtual || treadmill,
      race: summary["workout_type"] == RACE_WORKOUT_TYPE,
      distance_m: summary["distance"],
      timer_s: moving&.positive? ? moving : elapsed,
      moving_s: moving,
      elapsed_s: elapsed,
      elevation_gain_m: summary["total_elevation_gain"],
      avg_hr: summary["average_heartrate"]&.round,
      max_hr: summary["max_heartrate"]&.round,
      avg_cadence: cadence && cadence * 2,
      start_lat: summary.dig("start_latlng", 0),
      start_lng: summary.dig("start_latlng", 1),
      summary:
    }
  end

  private
  def parse_time(value)
    Time.iso8601(value) if value
  rescue ArgumentError
    nil
  end
end
