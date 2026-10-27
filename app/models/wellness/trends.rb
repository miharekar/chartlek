class Wellness::Trends
  DEFAULT_WINDOW = 1.year
  SERIES = {
    rhr: :resting_hr,
    hrv: :hrv_last_night,
    hrv_low: :hrv_baseline_low,
    hrv_high: :hrv_baseline_high,
    status: :hrv_status,
    bb_high: :body_battery_high,
    bb_low: :body_battery_low,
    bb_wake: :body_battery_wake,
    stress: :stress_avg,
    weight: :weight_kg
  }.freeze
  WEEK = Arel.sql("date(local_started_at, 'weekday 0', '-6 days')")
  ZONE_SECONDS = [
    Arel.sql("SUM(json_extract(summary, '$.hrTimeInZone_1'))"),
    Arel.sql("SUM(json_extract(summary, '$.hrTimeInZone_2'))"),
    Arel.sql("SUM(json_extract(summary, '$.hrTimeInZone_3'))"),
    Arel.sql("SUM(json_extract(summary, '$.hrTimeInZone_4'))"),
    Arel.sql("SUM(json_extract(summary, '$.hrTimeInZone_5'))")
  ].freeze

  def initialize(from: nil, to: nil)
    @from = parse_date(from)
    @to = parse_date(to)
  end

  def data?
    dates.any? && charts.any?
  end

  def charts
    {
      rhr: columns[:rhr],
      hrv: columns[:hrv],
      bb: columns[:bb_high] && columns[:bb_low],
      stress: columns[:stress],
      weight: columns[:weight],
      vdot: vdot.any?,
      zones: zones.any?
    }.select { |_, present| present }.keys
  end

  def payload
    {
      start: to_ms(dates.first),
      domain: [to_ms(dates.first), to_ms(dates.last)],
      window: [to_ms(window_start), to_ms(window_end)],
      columns:,
      vdot:,
      zones:
    }
  end

  private
  def dates
    rows.map(&:first)
  end

  def rows
    @rows ||= WellnessDay.order(:date).pluck(:date, *SERIES.values).reject { |_, *values| values.all?(&:nil?) }
  end

  def columns
    @columns ||= dense.transpose.then { |series| SERIES.keys.zip(series) }.reject { |_, values| values.all?(&:nil?) }.to_h
  end

  def dense
    by_date = rows.to_h { |date, *values| [date, values] }
    blank = Array.new(SERIES.size)

    (dates.first..dates.last).map { by_date.fetch(it, blank) }
  end

  def vdot
    @vdot ||= PaceTrend.new.then { |trend| trend.runs.select { trend.top_ids.include?(it.id) }.map { [ms(it.local_started_at), it.vdot.round(2)] } }
  end

  def zones
    @zones ||= Activity.group(WEEK).order(WEEK).pluck(WEEK, *ZONE_SECONDS).filter_map do |week, *seconds|
      seconds = seconds.map { it.to_f.round }
      [to_ms(Date.iso8601(week)), *seconds] if seconds.any?(&:positive?)
    end
  end

  def window_start
    @from || [dates.last - DEFAULT_WINDOW, dates.first].max
  end

  def window_end
    (@to || dates.last) + 1
  end

  def ms(time)
    time.to_i * 1000
  end

  def to_ms(date)
    date.in_time_zone("UTC").to_i * 1000
  end

  def parse_date(value)
    Date.iso8601(value) if value.is_a?(String)
  rescue Date::Error
    nil
  end
end
