class Overview::Scatter
  def initialize(activities)
    @activities = activities
  end

  def data
    {runs: @activities.map { row(it) }, last: @activities.size - 1, average:}
  end

  private
  def row(activity)
    {t: activity.local_started_at.to_i * 1000, name: activity.name, km: (activity.distance_m / 1000).round(2), pace: activity.pace.round(1), hr: activity.avg_hr, spi: activity.spi&.round(1), href: Rails.application.routes.url_helpers.run_path(activity)}
  end

  def average
    km = @activities.sum(&:distance_m) / 1000.0
    hrs = @activities.filter_map(&:avg_hr)
    spis = @activities.filter_map(&:spi)

    {
      km: (km / @activities.size).round(2),
      pace: (@activities.sum(&:timer_s) / km).round(1),
      hr: (hrs.sum.to_f / hrs.size if hrs.any?)&.round(1),
      spi: (spis.sum / spis.size if spis.any?)&.round(1)
    }
  end
end
