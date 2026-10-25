class Track::Fit
  def self.parse(path)
    new(Fit4Ruby.read(path)).recording
  rescue Fit4Ruby::Error => error
    raise Track::Error, "Unreadable FIT file: #{error.message}"
  end

  def initialize(activity)
    @activity = activity
  end

  def recording
    raise Track::Error, "FIT file has no records" if @activity.records.empty?

    first = @activity.records.first.timestamp
    pauses = self.pauses

    Track::Recording.new(@activity.records.map { row(it, first, pauses) })
  end

  private
  def row(record, first, pauses)
    paused = pauses.sum { |from, to| (to <= record.timestamp) ? to - from : 0 }

    {
      at: record.timestamp.to_f,
      t: record.timestamp - first - paused,
      d: record.distance,
      lat: record.position_lat,
      lng: record.position_long,
      alt: record.altitude || record.enhanced_elevation,
      hr: record.heart_rate,
      cad: record.run_cadence
    }
  end

  def pauses
    stopped = nil

    @activity.events.select { it.event == "timer" }.each_with_object([]) do |event, pauses|
      if event.event_type == "stop_all"
        stopped ||= event.timestamp
      elsif event.event_type == "start_time" && stopped
        pauses << [stopped, event.timestamp]
        stopped = nil
      end
    end
  end
end
