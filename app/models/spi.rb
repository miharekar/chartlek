class Spi
  MIN_DISTANCE_M = 400
  MAX = 1000
  RECORD_POINTS = 1035
  WALK_DISTANCE_M = 5000
  WALK_SECONDS = 3600
  TABLE_STEPS = [[1, 100, 0.5], [100, 300, 1], [300, 600, 2], [600, 1000, 4]].freeze
  RUNNING_CURVE = [
    [-11.15895, 3.796158e-2],
    [4.304605, 1.646772e-3],
    [0.5234627, 4.107670e-4],
    [4.031560, 7.068099e-6],
    [2.316157, 5.220990e-9]
  ].freeze

  class << self
    def for(distance_m, seconds)
      scale_points(points(distance_m, seconds)) if distance_m >= MIN_DISTANCE_M && seconds > 0
    end

    def time_for(distance_m, spi)
      target = walk_points + (spi - 1) * (MAX - walk_points) / 999.0
      scale = scale_for(distance_m)
      scale * record_time(distance_m) / (target + scale - RECORD_POINTS)
    end

    def time_table(distance_m)
      table_spis.map { [it, time_for(distance_m, it).round(1)] }
    end

    def points(distance_m, seconds)
      scale = scale_for(distance_m)
      scale * (record_time(distance_m) / seconds - 1 + RECORD_POINTS / scale)
    end

    private
    def table_spis
      TABLE_STEPS.flat_map { |from, to, step| (from...to).step(step).to_a } + [MAX]
    end
    def scale_points(points)
      (1 + 999 * (points - walk_points) / (MAX - walk_points)).clamp(1, MAX)
    end

    def walk_points
      points(WALK_DISTANCE_M, WALK_SECONDS)
    end

    def scale_for(distance_m)
      85 / (0.0654 - 0.00258 * record_velocity(distance_m))
    end

    def record_time(distance_m)
      distance_m / record_velocity(distance_m)
    end

    def record_velocity(distance_m)
      RUNNING_CURVE.sum { |b, r| b * Math.exp(-r * distance_m) }
    end
  end
end
