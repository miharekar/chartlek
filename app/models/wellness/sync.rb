class Wellness::Sync
  METRICS = %i[summary hrv weight]
  REFRESH_DAYS = 3
  CHUNK_DAYS = 30
  STOP_AFTER = 6
  MARKER_FINAL_AFTER = 7.days

  delegate :request_count, to: :@client

  def initialize(client: Garmin::Client.new)
    @client = client
  end

  def refresh(today: Date.current)
    sync_hr_zones
    METRICS.each { collect(it, today - REFRESH_DAYS, today) }
    Profile.instance.update!(wellness_synced_at: Time.current)
  end

  def backfill(from:, to: Date.current)
    active = METRICS.dup
    empty = Hash.new(0)
    report = METRICS.index_with { 0 }
    cursor = to

    while cursor >= from && active.any?
      first = [cursor - CHUNK_DAYS + 1, from].max

      active.dup.each do |metric|
        found = collect(metric, first, cursor, resume: true)
        report[metric] += found
        empty[metric] = found.zero? ? empty[metric] + 1 : 0
        active.delete(metric) if empty[metric] >= STOP_AFTER
      end

      cursor = first - 1
    end

    sync_hr_zones
    Profile.instance.update!(wellness_synced_at: Time.current)
    report
  end

  private
  def collect(metric, from, to, resume: false)
    case metric
    when :summary then collect_summaries(from, to, resume:)
    when :hrv then collect_hrv(from, to)
    when :weight then collect_weight(from, to)
    end
  end

  def collect_summaries(from, to, resume:)
    known = resume ? WellnessDay.where(date: from..to).select { settled?(it) }.map(&:date) : []

    ((from..to).to_a - known).each do |date|
      payload = @client.daily_summary(date)
      attributes = summary_attributes(payload)

      store(date, "summary", attributes.values.any? ? payload : {}, attributes)
    end

    WellnessDay.where(date: from..to).count { it.raw["summary"].present? }
  end

  def settled?(day)
    summary = day.raw["summary"]

    summary.present? || (summary == {} && day.updated_at > day.date.in_time_zone("UTC") + MARKER_FINAL_AFTER)
  end

  def collect_hrv(from, to)
    summaries = @client.hrv_range(from, to)&.dig("hrvSummaries").to_a

    summaries.count do |payload|
      baseline = payload["baseline"] || {}
      attributes = {
        hrv_last_night: payload["lastNightAvg"],
        hrv_weekly_avg: payload["weeklyAvg"],
        hrv_baseline_low: baseline["balancedLow"],
        hrv_baseline_high: baseline["balancedUpper"],
        hrv_status: payload["status"]
      }

      store(Date.parse(payload["calendarDate"]), "hrv", payload, attributes) if attributes.values.any?
    end
  end

  def collect_weight(from, to)
    summaries = @client.weight_range(from, to)&.dig("dailyWeightSummaries").to_a

    summaries.count do |payload|
      grams = payload.dig("latestWeight", "weight")

      store(Date.parse(payload["summaryDate"]), "weight", payload, weight_kg: grams && grams / 1000.0) if grams
    end
  end

  def summary_attributes(payload)
    {
      resting_hr: payload&.dig("restingHeartRate"),
      resting_hr_avg_7d: payload&.dig("lastSevenDaysAvgRestingHeartRate"),
      stress_avg: payload&.dig("averageStressLevel"),
      body_battery_high: payload&.dig("bodyBatteryHighestValue"),
      body_battery_low: payload&.dig("bodyBatteryLowestValue"),
      body_battery_wake: payload&.dig("bodyBatteryAtWakeTime")
    }
  end

  def store(date, key, payload, attributes)
    day = WellnessDay.find_by(date:) || claim(date)
    merged = day.raw[key].to_h.merge(payload.to_h.compact)

    day.update!(attributes.compact.merge(raw: day.raw.merge(key => merged)))
    day.saved_changes? || day.update!(updated_at: Time.current)
  end

  def claim(date)
    WellnessDay.create!(date:)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    WellnessDay.find_by!(date:)
  end

  def sync_hr_zones
    zones = @client.hr_zones.to_a
    entry = zones.find { it["sport"] == "RUNNING" } || zones.find { it["sport"] == "DEFAULT" }
    floors = entry && (1..5).map { entry["zone#{it}Floor"] }

    Profile.instance.update!(hr_zones: {"source" => "garmin", "sport" => entry["sport"], "floors" => floors, "max_hr" => entry["maxHeartRateUsed"]}) if floors&.all? && entry["maxHeartRateUsed"]
  rescue Garmin::Client::InvalidKey
    raise
  rescue Garmin::Client::Error => error
    Rails.logger.warn("Garmin HR zones skipped: #{error.message.truncate(200)}")
  end
end
