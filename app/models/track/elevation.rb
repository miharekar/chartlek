class Track::Elevation
  BIN_M = 100.0
  THRESHOLD_M = 1.0
  EPSILON_M = 1e-6

  def initialize(rows)
    @rows = rows
    @bins = (0.0...rows.last[:d]).step(BIN_M).map { {distance: [BIN_M, rows.last[:d] - it].min, gain: nil, loss: nil} }
  end

  def bins
    @result ||= calculate
  end

  private
  def calculate
    return if @bins.empty?

    turning = @rows.first if @rows.first[:alt]

    @rows.each_cons(2) do |previous, current|
      known = previous[:alt] && current[:alt]
      segments(previous[:d], current[:d]) do |bin, _, spans|
        next unless spans

        if known
          bin[:gain] ||= 0.0
          bin[:loss] ||= 0.0
        else
          bin[:missing] = true
        end
      end

      if known && turning
        change = current[:alt] - turning[:alt]
        if change.abs > THRESHOLD_M
          key = change.positive? ? :gain : :loss
          segments(previous[:d], current[:d]) do |bin, fraction, _|
            bin[:gain] ||= 0.0
            bin[:loss] ||= 0.0
            bin[key] += change.abs * fraction
          end
          turning = current
        end
      else
        turning = current[:alt] ? current : nil
      end
    end

    @bins if @bins.any? { !it[:gain].nil? }
  end

  def segments(from, to)
    if to - from < EPSILON_M
      yield @bins[[(from / BIN_M).floor, @bins.size - 1].min], 1.0, false
    else
      first = [(from / BIN_M).floor, @bins.size - 1].min
      last = [[(to / BIN_M).ceil - 1, first].max, @bins.size - 1].min

      (first..last).each do |index|
        overlap = [to, (index + 1) * BIN_M].min - [from, index * BIN_M].max
        yield @bins[index], overlap / (to - from), true if overlap >= EPSILON_M
      end
    end
  end
end
