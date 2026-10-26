module Activity::Performance
  extend ActiveSupport::Concern

  PAUSE_THRESHOLD_S = 60
  FLAT_M_PER_KM = 1.5
  HILL_STEP_M_PER_KM = 8.0
  MAX_HILL_DIFFICULTY = 5

  included do
    before_save :assign_performance
  end

  def paused?
    elapsed_s.present? && elapsed_s - timer_s >= PAUSE_THRESHOLD_S
  end

  def pace
    timer_s / distance_m * 1000
  end

  def hill_difficulty
    if elevation_gain_m
      gain_per_km = elevation_gain_m / (distance_m / 1000)

      if gain_per_km < FLAT_M_PER_KM
        1
      else
        [1 + (gain_per_km / HILL_STEP_M_PER_KM).ceil, MAX_HILL_DIFFICULTY].min
      end
    end
  end

  private
  def assign_performance
    self.vdot = Vdot.for(distance_m, timer_s)
  end
end
