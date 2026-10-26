class Track::Metrics
  SPLIT_M = 1000.0
  SEGMENTS = 20
  WINDOW_S = 10

  def initialize(recording)
    @rows = recording.rows
    @t = @rows.pluck(:t)
    @d = @rows.pluck(:d)
  end

  def splits(size = SPLIT_M)
    (0.0...@d.last).step(size).filter_map { split(it, [it + size, @d.last].min) }
  end

  def pace_profile
    length = @d.last / SEGMENTS

    Array.new(SEGMENTS) { pace(it * length, (it + 1) * length).round(1) }
  end

  def pace_variability
    if speed_windows
      mean = speed_windows.sum / speed_windows.size
      (speed_windows.sum { (it - mean).abs } / speed_windows.size / mean * 100).round(1)
    end
  end

  def chart_metrics
    {speed_windows: speed_windows&.map { it.round(2) }, elevation: elevation_bins}
  end

  def speed_windows
    @speed_windows ||= begin
      windows = (@t.last / WINDOW_S).floor
      covered = Array.new(windows) { interpolate(@t, @d, (it + 1) * WINDOW_S) - interpolate(@t, @d, it * WINDOW_S) }
      covered if windows > 1 && covered.sum.positive?
    end
  end

  private
  def elevation_bins
    return @elevation_bins if defined?(@elevation_bins)

    @elevation_bins = Track::Elevation.new(@rows).bins&.map { it.transform_values { |value| value.is_a?(Float) ? value.round(2) : value } }
  end

  def split(from, to)
    if to - from >= 1
      first = @d.bsearch_index { it > from }
      samples = @rows[first...(@d.bsearch_index { it > to } || @rows.size)]
      gain, loss = elevation_change(from, to)

      {
        distance: (to - from).round(1),
        time: (interpolate(@d, @t, to) - interpolate(@d, @t, from)).round(1),
        pace: pace(from, to).round(1),
        hr: average(samples, :hr)&.round,
        cad: average(samples, :cad)&.round,
        gain: gain&.round(1),
        loss: loss&.round(1)
      }
    end
  end

  def elevation_change(from, to)
    if elevation_bins
      known = elevation_bins[(from / Track::Elevation::BIN_M).floor..[(to / Track::Elevation::BIN_M).ceil - 1, elevation_bins.size - 1].min].select { it[:gain] }

      [known.sum { it[:gain] }, known.sum { it[:loss] }] if known.any?
    end
  end

  def pace(from, to)
    (interpolate(@d, @t, to) - interpolate(@d, @t, from)) / ((to - from) / 1000.0)
  end

  def average(samples, key)
    values = samples.filter_map { it[key] }
    values.sum.fdiv(values.size) if values.any?
  end

  def interpolate(xs, ys, x)
    index = xs.bsearch_index { it >= x }

    if index.nil?
      ys.last
    elsif index.zero?
      ys.first
    else
      ys[index - 1] + (x - xs[index - 1]) / (xs[index] - xs[index - 1]) * (ys[index] - ys[index - 1])
    end
  end
end
