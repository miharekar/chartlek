module Activity::Performance
  extend ActiveSupport::Concern

  PAUSE_THRESHOLD_S = 60
  FLAT_M_PER_KM = 1.5
  MIN_PACE_DISTANCE_M = 100
  HILL_STEP_M_PER_KM = 8.0
  MAX_HILL_DIFFICULTY = 5
  WORKOUT_STEPS = %w[INTERVAL_WARMUP INTERVAL_ACTIVE INTERVAL_RECOVERY INTERVAL_REST INTERVAL_COOLDOWN].freeze
  WORKOUT_ONLY_STEPS = (WORKOUT_STEPS - %w[INTERVAL_ACTIVE]).freeze
  WORKOUT_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM json_each(summary, '$.splitSummaries') WHERE json_extract(value, '$.splitType') IN (#{WORKOUT_ONLY_STEPS.map { "'#{it}'" }.join(", ")}) OR (json_extract(value, '$.splitType') = 'INTERVAL_ACTIVE' AND json_extract(value, '$.noOfSplits') > 1))
  SQL

  included do
    before_save :assign_performance
  end

  def paused?
    elapsed_s.present? && elapsed_s - timer_s >= PAUSE_THRESHOLD_S
  end

  def pace
    timer_s / distance_m * 1000
  end

  def grade_adjusted_pace
    speed = summary&.dig("avgGradeAdjustedSpeed")
    1000 / speed if speed.to_f.positive?
  end

  def garmin_pr?
    has_attribute?(:garmin_pr) ? garmin_pr == 1 : summary&.dig("pr") == true
  end

  def workout?
    if has_attribute?(:garmin_workout)
      garmin_workout == 1
    else
      steps = workout_steps
      steps.any? { WORKOUT_ONLY_STEPS.include?(it["splitType"]) } || steps.any? { it["splitType"] == "INTERVAL_ACTIVE" && it["noOfSplits"].to_i > 1 }
    end
  end

  def workout_splits
    if workout?
      workout_steps.sort_by { WORKOUT_STEPS.index(it["splitType"]) }.map do |step|
        distance = step["distance"].to_f
        duration = step["duration"].to_f
        {type: step["splitType"], count: (step["noOfSplits"] if step["noOfSplits"].to_i > 1), distance_m: distance, duration_s: duration, pace: (duration / distance * 1000 if distance >= MIN_PACE_DISTANCE_M)}
      end
    end
  end

  def performance_zone
    PaceZones.zone_for_vdot(vdot) if vdot
  end

  def performance_zone_range
    PaceZones.range(Activity.where.not(vdot: nil).pluck(:vdot), performance_zone) if vdot
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
  def workout_steps
    Array(summary&.dig("splitSummaries")).select { WORKOUT_STEPS.include?(it["splitType"]) }
  end

  def assign_performance
    self.vdot = Vdot.for(distance_m, timer_s)
  end
end
