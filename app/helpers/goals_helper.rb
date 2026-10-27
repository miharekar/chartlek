module GoalsHelper
  def goal_period_label(goal)
    "#{goal.period.capitalize}ly"
  end

  def goal_gap(progress)
    if progress.complete?
      ["Reached"]
    elsif progress.elapsed_days.zero?
      ["Not started"]
    elsif progress.days_left.zero?
      [overview_distance(progress.remaining_km), "km short"]
    elsif progress.ahead_km < 0
      [overview_distance(-progress.ahead_km), "km behind"]
    else
      [overview_distance(progress.ahead_km), "km ahead"]
    end
  end

  def goal_status(progress)
    goal_gap(progress).join(" ")
  end

  def goal_status_class(progress)
    if progress.behind? || (progress.days_left.zero? && !progress.complete?)
      "text-red-700 dark:text-red-400"
    else
      WidgetsHelper::ACCENT
    end
  end

  def goal_required(progress)
    if progress.complete? || progress.days_left.zero?
      nil
    else
      "#{overview_distance(progress.required_km_per_day)} km/day"
    end
  end
end
