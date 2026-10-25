class Track::Smashrun
  NO_FIX = -1.0

  def self.parse(json)
    new(JSON.parse(json)).recording
  end

  def initialize(body)
    @series = Array(body["recordingKeys"]).zip(Array(body["recordingValues"])).to_h
    @pause_indexes = body["pauseIndexes"] || []
  end

  def recording
    raise Track::Error, "Smashrun activity has no recording" unless @series["clock"]

    Track::Recording.new(timer.each_with_index.map { |t, index| row(t, index) })
  end

  private
  def timer
    if @series["duration"]
      @series["duration"]
    else
      clock = @series["clock"]
      paused = 0.0

      clock.each_with_index.map do |seconds, index|
        paused += seconds - clock[index - 1] if @pause_indexes.include?(index) && index.positive?
        seconds - paused
      end
    end
  end

  def row(t, index)
    lat = value("latitude", index)
    lng = value("longitude", index)
    fixed = !(lat == NO_FIX && lng == NO_FIX)

    {
      t:,
      d: value("distance", index)&.*(1000),
      lat: (lat if fixed),
      lng: (lng if fixed),
      alt: value("elevation", index),
      hr: value("heartRate", index),
      cad: value("cadence", index)&.*(2)
    }
  end

  def value(key, index)
    @series[key]&.at(index)
  end
end
