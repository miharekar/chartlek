class Overview::Bars
  def initialize(activities, period)
    @period = period
    @groups = activities.group_by { start_of(it.local_started_at.to_date) }
  end

  def data
    {granularity: @period.granularity, buckets: @period.range.map { start_of(it) }.uniq.map { bucket(it, @groups[it] || []) }}
  end

  private
  def start_of(date)
    case @period.granularity
    when :month then date.beginning_of_month
    when :week then date.beginning_of_week
    else date
    end
  end

  def bucket(from, runs)
    distance_km = runs.sum(&:distance_m) / 1000.0
    spis = runs.filter_map(&:spi)

    {
      from: from.iso8601,
      runs: runs.size,
      distance: distance_km.round(2),
      elevation: runs.sum { it.elevation_gain_m.to_f }.round,
      avg_distance: (runs.any? ? (distance_km / runs.size).round(2) : nil),
      avg_pace: (runs.any? ? (runs.sum(&:timer_s) / distance_km).round(1) : nil),
      avg_spi: (spis.any? ? (spis.sum / spis.size).round(1) : nil),
      href: href(from, runs)
    }
  end

  def href(from, runs)
    if runs.any?
      if @period.granularity == :day
        Rails.application.routes.url_helpers.run_path(runs.first)
      else
        Rails.application.routes.url_helpers.overview_period_path(link_date(from).year, link_date(from).month)
      end
    end
  end

  def link_date(from)
    [from, @period.first].max
  end
end
