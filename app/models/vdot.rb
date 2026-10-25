class Vdot
  MIN_DISTANCE_M = 400
  FASTEST_SPEED_MS = 10.0
  SLOWEST_SPEED_MS = 0.5
  TABLE_MAX = 90
  TABLE_STEPS = [[10, 12, 0.05], [12, 30, 0.1], [30, 50, 0.2], [50, 60, 0.25], [60, 90, 0.5]].freeze

  class << self
    def for(distance_m, seconds)
      if distance_m >= MIN_DISTANCE_M && seconds > 0
        minutes = seconds / 60.0
        oxygen_cost(distance_m / minutes) / fraction_of_max(minutes)
      end
    end

    def time_for(distance_m, vdot)
      low = distance_m / FASTEST_SPEED_MS
      high = distance_m / SLOWEST_SPEED_MS

      100.times do
        middle = (low + high) / 2

        if self.for(distance_m, middle) > vdot
          low = middle
        else
          high = middle
        end
      end

      (low + high) / 2
    end

    def time_table(distance_m)
      table_vdots.map { [it, time_for(distance_m, it).round(1)] }
    end

    private
    def table_vdots
      TABLE_STEPS.flat_map { |from, to, step| (from...to).step(step).map { it.round(2) } } + [TABLE_MAX]
    end
    def oxygen_cost(velocity)
      -4.60 + 0.182258 * velocity + 0.000104 * velocity**2
    end

    def fraction_of_max(minutes)
      0.8 + 0.1894393 * Math.exp(-0.012778 * minutes) + 0.2989558 * Math.exp(-0.1932605 * minutes)
    end
  end
end
