module Activity::Performance
  extend ActiveSupport::Concern

  PAUSE_THRESHOLD_S = 60

  included do
    before_save :assign_performance
  end

  def paused?
    elapsed_s.present? && elapsed_s - timer_s >= PAUSE_THRESHOLD_S
  end

  def pace
    timer_s / distance_m * 1000
  end

  private
  def assign_performance
    self.vdot = Vdot.for(distance_m, timer_s)
  end
end
