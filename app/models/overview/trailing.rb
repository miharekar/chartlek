class Overview::Trailing
  def initialize(activities, period)
    @activities = activities
    @period = period
    @window = period.trailing_days
  end

  def data
    {days: @window, points:}
  end

  private
  def points
    running = ((@period.first - (@window - 1))..@period.first).sum { totals[it] }

    @period.range.each_with_index.map do |date, index|
      running += totals[date] - totals[date - @window] if index > 0
      [date.iso8601, [running, 0].max.round(1)]
    end
  end

  def totals
    @totals ||= @activities.each_with_object(Hash.new(0.0)) { |activity, sums| sums[activity.local_started_at.to_date] += activity.distance_m / 1000.0 }
  end
end
