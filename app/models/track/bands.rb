class Track::Bands
  WINDOW_M = 100.0
  WINDOW_S = 30.0
  GRADE_MIN_M = 20.0
  GRADE_EDGES = [-8, -4, -1, 1, 4, 8].freeze
  GRADE_COUNT = GRADE_EDGES.size + 1

  Window = Struct.new(:seconds, :meters, :climb, :bpm)

  def initialize(data, hr_zones)
    @data = data.stringify_keys
    @hr_zones = hr_zones
  end

  def to_h
    pace = Array.new(PaceZones::COUNT, 0.0)
    hr = Array.new(HrZones::ZONES.size, 0.0)
    grade = Array.new(GRADE_COUNT, 0.0)

    windows.each do |window|
      pace[PaceZones.zone_for(window.meters / window.seconds * 3.6)] += window.seconds
      hr[hr_zone(window) - 1] += window.seconds if hr_zone(window)
      grade[grade_bucket(window)] += window.seconds if grade_bucket(window)
    end

    {"pace" => seconds(pace), "hr" => seconds(hr), "grade" => seconds(grade)}
  end

  private
  attr_reader :data, :hr_zones

  def windows
    t, d = data.values_at("t", "d")
    from = 0

    (1...t.size).filter_map do |index|
      if d[index] - d[from] >= WINDOW_M || t[index] - t[from] >= WINDOW_S || index == t.size - 1
        window = build(from, index)
        from = index
        window if window.seconds.positive?
      end
    end
  end

  def build(from, to)
    t, d, alt, hr = data.values_at("t", "d", "alt", "hr")
    bpms = hr&.values_at(*from..to)&.compact
    climb = alt[to] - alt[from] if alt && alt[to] && alt[from]

    Window.new(t[to] - t[from], d[to] - d[from], climb, (bpms.sum / bpms.size if bpms&.any?))
  end

  def hr_zone(window)
    (hr_zones.zone(window.bpm) || 1) if hr_zones && window.bpm
  end

  def grade_bucket(window)
    GRADE_EDGES.count { window.climb / window.meters * 100 >= it } if window.climb && window.meters >= GRADE_MIN_M
  end

  def seconds(values)
    values.map(&:round) if values.any?(&:positive?)
  end
end
