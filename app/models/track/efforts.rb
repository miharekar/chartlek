class Track::Efforts
  DISTANCES = [[250, "250 m"], [400, "400 m"], [1000, "1 km"], [5000, "5 km"], [10_000, "10 km"], [21_097.5, "Half marathon"], [42_195, "Marathon"]].freeze

  def initialize(data)
    @t = data.fetch("t", [])
    @d = data.fetch("d", [])
  end

  def all
    DISTANCES.filter_map { |distance, label| effort(distance, label) if @d.any? && distance <= @d.last - @d.first }
  end

  private
  def effort(distance, label)
    from = starts(distance).min_by { time_at(it + distance) - time_at(it) }
    time = time_at(from + distance) - time_at(from)

    {label:, distance:, from:, to: from + distance, time:, pace: time / (distance / 1000.0), vdot: Vdot.for(distance, time)}
  end

  def starts(distance)
    last = @d.last - distance
    (@d + @d.map { it - distance }).select { it.between?(@d.first, last) }
  end

  def time_at(distance)
    index = @d.bsearch_index { it >= distance }

    if index.nil?
      @t.last
    elsif index.zero?
      @t.first
    else
      @t[index - 1] + (distance - @d[index - 1]).fdiv(@d[index] - @d[index - 1]) * (@t[index] - @t[index - 1])
    end
  end
end
