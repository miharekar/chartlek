class Track::Recording
  SERIES = %i[t d lat lng alt hr cad]
  ROUNDING = {t: 1, d: 1, lat: 5, lng: 5, alt: 1}
  MAX_POINTS = 2000
  DISTANCE_TOLERANCE = 0.1
  STILL_MPS = 0.5

  attr_reader :rows

  def initialize(rows, rebuilt: false)
    @rows = normalize(rows)
    @rebuilt = rebuilt
  end

  def rebuilt?
    @rebuilt
  end

  delegate :size, to: :rows

  def clip(from, timer)
    if rows.first[:at]
      started = self.class.new(rows.select { it[:at] >= from })
      self.class.new(started.rows.select { it[:t] <= timer })
    else
      self
    end
  end

  def with_distance(distance_m)
    raise Track::Error, "Fewer than 2 records" if size < 2
    raise Track::Error, "No timer time" unless rows.last[:t].positive?

    if (rows.last[:d] - distance_m).abs > distance_m * DISTANCE_TOLERANCE
      total = rows.last[:t]
      self.class.new(rows.map { it.merge(d: it[:t] / total * distance_m) }, rebuilt: true)
    else
      self
    end
  end

  def without_stops(timer)
    excess = rows.last[:t] - timer

    if rebuilt? || !excess.positive?
      self
    else
      removed = stalls.sort_by { -it.last }.each_with_object({}) do |(index, dt), taken|
        taken[index] = [dt, excess].min if excess.positive?
        excess -= dt
      end
      shift = 0.0

      self.class.new(rows.each_with_index.map { |row, index| row.merge(t: row[:t] - (shift += removed.fetch(index, 0.0))) })
    end
  end

  def data
    SERIES.index_with { |key| picked.map { round(key, it[key]) } }.reject { |_, values| values.all?(&:nil?) }
  end

  private
  def normalize(rows)
    first = rows.first
    last_d = 0.0

    rows.map do |row|
      last_d = [last_d, row[:d]].compact.max
      row.merge(t: row[:t] - first[:t], d: last_d - (first[:d] || 0.0), hr: row[:hr]&.nonzero?, cad: row[:cad]&.nonzero?)
    end
  end

  def stalls
    rows.each_cons(2).each_with_index.filter_map do |(from, to), index|
      dt = to[:t] - from[:t]
      [index + 1, dt] if dt.positive? && (to[:d] - from[:d]) / dt < STILL_MPS
    end
  end

  def picked
    if size > MAX_POINTS
      Array.new(MAX_POINTS) { rows[(it * (size - 1) / (MAX_POINTS - 1.0)).round] }
    else
      rows
    end
  end

  def round(key, value)
    value&.round(ROUNDING.fetch(key, 0))
  end
end
