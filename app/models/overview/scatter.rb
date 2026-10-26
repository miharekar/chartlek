class Overview::Scatter
  def initialize(activities)
    @activities = activities
  end

  def data
    {runs: @activities.map { row(it) }, last: @activities.size - 1, average:}
  end

  private
  def row(activity)
    {t: activity.local_started_at.to_i * 1000, name: activity.name, km: (activity.distance_m / 1000).round(2), pace: activity.pace.round(1), hr: activity.avg_hr, elev: activity.elevation_gain_m&.round, vdot: activity.vdot&.round(2), href: Rails.application.routes.url_helpers.run_path(activity)}
  end

  def average
    km = @activities.sum(&:distance_m) / 1000.0

    {
      pace: {km: mean_km(@activities), value: (@activities.sum(&:timer_s) / km).round(1)},
      hr: mean(@activities.select(&:avg_hr), 1, &:avg_hr),
      vdot: mean(@activities.select(&:vdot), 2, &:vdot)
    }
  end

  def mean_km(activities)
    (activities.sum(&:distance_m) / 1000.0 / activities.size).round(2)
  end

  def mean(activities, digits, &value)
    {km: mean_km(activities), value: (activities.sum(&value).to_f / activities.size).round(digits)} if activities.any?
  end
end
