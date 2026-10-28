class Track::Steps
  TYPES = {
    "warmup" => "warmup",
    "active" => "active",
    "Undocumented value 5" => "active",
    "Undocumented value 4" => "recovery",
    "rest" => "rest",
    "cooldown" => "cooldown"
  }.freeze
  MERGED = %w[warmup cooldown].freeze

  def initialize(recording)
    @rows = recording.rows
    @laps = recording.laps
  end

  def to_a
    types = laps.map { TYPES[it[:intensity]] }

    if types.uniq.size > 1 && types.none?(nil) && rows.first[:at]
      starts = merged(laps.zip(types))
      boundaries = starts.map(&:last) + [rows.last[:at]]
      distances = boundaries.map { interpolate(:d, it) }
      times = boundaries.map { interpolate(:t, it) }

      starts.each_with_index.filter_map do |(type, _), index|
        {type:, from: distances[index].round(1), to: distances[index + 1].round(1), time: (times[index + 1] - times[index]).round(1)} if distances[index + 1] > distances[index]
      end.presence
    end
  end

  private
  attr_reader :rows, :laps

  def merged(typed)
    typed.each_with_object([]) do |(lap, type), steps|
      steps << [type, lap[:at]] unless steps.last&.first == type && MERGED.include?(type)
    end
  end

  def interpolate(key, at)
    index = times.bsearch_index { it >= at }

    if index.nil?
      rows.last[key]
    elsif index.zero?
      rows.first[key]
    else
      before = rows[index - 1]
      before[key] + (at - times[index - 1]) / (times[index] - times[index - 1]) * (rows[index][key] - before[key])
    end
  end

  def times
    @times ||= rows.pluck(:at)
  end
end
