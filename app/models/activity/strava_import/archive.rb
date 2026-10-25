class Activity::StravaImport::Archive
  TIME_ZONE = "Europe/Ljubljana"
  DATE_FORMAT = "%b %d, %Y, %I:%M:%S %p"
  TYPES = {"Run" => "running", "Trail Run" => "trail_running"}
  INDOOR_TYPES = %w[virtual_run]

  def initialize(path)
    @path = path
  end

  def rows
    header, *records = CSV.read(path, encoding: "bom|utf-8", skip_blanks: true)
    keys = unique_keys(header.map { it.to_s.strip })

    records.map { |record| keys.zip(record.map { it&.strip.presence }).to_h }
  end

  def run?(row)
    row["Activity Type"].to_s.match?(/run/i)
  end

  def attributes_for(row)
    started_at = parse_time(row["Activity Date"])
    type = row["Activity Type"].parameterize(separator: "_")
    moving = number(row["Moving Time"])
    elapsed = number(row["Elapsed Time"])

    {
      source: "strava",
      external_id: row["Activity ID"],
      started_at:,
      local_started_at: started_at && started_at + started_at.in_time_zone(TIME_ZONE).utc_offset.seconds,
      name: row["Activity Name"],
      activity_type: TYPES.fetch(row["Activity Type"], type),
      indoor: INDOOR_TYPES.include?(type),
      distance_m: number(row["Distance 2"]),
      timer_s: number(row["Timer Time"]) || moving || elapsed,
      moving_s: moving,
      elapsed_s: elapsed,
      elevation_gain_m: number(row["Elevation Gain"]),
      elevation_loss_m: number(row["Elevation Loss"]),
      avg_hr: number(row["Average Heart Rate"])&.round,
      max_hr: number(row["Max Heart Rate"])&.round,
      calories: number(row["Calories"])&.round,
      summary: row
    }
  end

  private
  attr_reader :path

  def unique_keys(names)
    seen = Hash.new(0)

    names.map do |name|
      seen[name] += 1
      (seen[name] == 1) ? name : "#{name} #{seen[name]}"
    end
  end

  def parse_time(value)
    ActiveSupport::TimeZone["UTC"].strptime(value, DATE_FORMAT) if value
  rescue ArgumentError
    nil
  end

  def number(value)
    Float(value, exception: false) if value
  end
end
