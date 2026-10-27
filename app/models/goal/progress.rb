class Goal::Progress
  RECENT_DAYS = 28

  attr_reader :goal, :today

  def initialize(goal, activities, today:)
    @goal = goal
    @activities = activities
    @today = today
  end

  def goal_km
    goal.distance_km
  end

  def elapsed_days
    [(last_date - goal.starts_on).to_i + 1, 0].max
  end

  def days_left
    if today > goal.ends_on
      0
    else
      (goal.ends_on - [today, goal.starts_on].max).to_i + 1
    end
  end

  def done_km
    cumulative.last || 0.0
  end

  def percent
    (100 * done_km / goal_km).round
  end

  def expected_km
    goal_km * expected_days / goal.days
  end

  def open_today?
    today.between?(goal.starts_on, goal.ends_on) && daily.none? { it[:index] == elapsed_days - 1 }
  end

  def ahead_km
    done_km - expected_km
  end

  def remaining_km
    [goal_km - done_km, 0.0].max
  end

  def required_km_per_day
    remaining_km / days_left if days_left.positive?
  end

  def recent_km_per_day
    @recent_km_per_day ||= begin
      recent = today - RECENT_DAYS + 1..today
      @activities.select { recent.cover?(it.local_started_at.to_date) }.sum(&:distance_m) / 1000.0 / RECENT_DAYS
    end
  end

  def catch_up_ratio
    required_km_per_day / recent_km_per_day if behind? && recent_km_per_day.positive?
  end

  def complete?
    done_km >= goal_km
  end

  def behind?
    elapsed_days.positive? && days_left.positive? && !complete? && ahead_km < 0
  end

  def cumulative
    @cumulative ||= begin
      totals = daily.to_h { [it[:index], it[:km]] }
      sum = 0.0
      Array.new(elapsed_days) { |index| sum += totals.fetch(index, 0.0) }
    end
  end

  def daily
    @daily ||= begin
      span = goal.starts_on..last_date
      @activities.select { span.cover?(it.local_started_at.to_date) }.group_by { it.local_started_at.to_date }.sort.map { |date, runs|
        longest = runs.max_by(&:distance_m)
        {index: (date - goal.starts_on).to_i, km: runs.sum(&:distance_m) / 1000.0, runs: runs.size, url: Rails.application.routes.url_helpers.run_path(longest.id)}
      }
    end
  end

  def payload
    {
      start: goal.starts_on.to_time(:utc).to_i * 1000,
      days: goal.days,
      goal_km: goal_km.round(3),
      cumulative: cumulative.map { it.round(3) },
      daily: daily.map { it.merge(km: it[:km].round(3)) },
      open_today: open_today?,
      ended: today > goal.ends_on,
      catch_up: ({ratio: catch_up_ratio&.round(2)} if behind?)
    }
  end

  private
  def expected_days
    open_today? ? elapsed_days - 1 : elapsed_days
  end

  def last_date
    [today, goal.ends_on].min
  end
end
