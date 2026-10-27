module Activity::Physiology
  extend ActiveSupport::Concern

  EFFORT = {
    aerobic: "aerobicTrainingEffect",
    anaerobic: "anaerobicTrainingEffect",
    label: "trainingEffectLabel",
    load: "activityTrainingLoad",
    body_battery: "differenceBodyBattery",
    moderate: "moderateIntensityMinutes",
    vigorous: "vigorousIntensityMinutes"
  }.freeze
  DYNAMICS = {
    ground_contact: "avgGroundContactTime",
    vertical_oscillation: "avgVerticalOscillation",
    stride_length: "avgStrideLength",
    vertical_ratio: "avgVerticalRatio",
    power: "avgPower",
    normalized_power: "normPower"
  }.freeze

  def hr_zone_times(zones = HrZones.for(self))
    seconds = hr_zones&.dig("seconds")&.map(&:to_f)
    seconds = HrZones::ZONES.map { summary&.dig("hrTimeInZone_#{it}").to_f } unless seconds&.sum&.positive?
    total = seconds.sum

    if total.positive?
      HrZones::ZONES.zip(seconds).map do |zone, time|
        range = zones&.range(zone)
        {zone:, seconds: time, percent: (time * 100 / total).round, from: range&.begin, to: range&.end}
      end
    end
  end

  def effort
    EFFORT.transform_values { summary&.dig(it) }.compact.reject { |key, value| value.is_a?(Numeric) && (value.zero? || (value.negative? && key != :body_battery)) }
  end

  def running_dynamics
    DYNAMICS.transform_values { summary&.dig(it) }.compact.select { |_, value| value.positive? }
  end

  def going_in
    day = WellnessDay.find_by(date: local_started_at.to_date)

    day.slice(:resting_hr, :resting_hr_avg_7d, :hrv_last_night, :hrv_status, :hrv_baseline_low, :hrv_baseline_high, :body_battery_wake, :sleep_s, :sleep_score).symbolize_keys.compact if day
  end
end
