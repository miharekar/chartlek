class Overview
  GoalSlot = Data.define(:goal, :progress)

  attr_reader :period, :activities

  def self.for(year: nil, month: nil)
    new(Activity.select(Activity.column_names - %w[summary splits weather bands hr_zones]), year:, month:)
  end

  def initialize(all, year: nil, month: nil, today: nil)
    @all = all.sort_by(&:local_started_at)
    @today = today || Activity.today
    @period = Period.new(year:, month:, today: @today, first_date: @all.first&.local_started_at&.to_date)
    @activities = @all.select { period.cover?(it.local_started_at.to_date) }
  end

  delegate :empty?, to: :activities

  def count
    activities.size
  end

  def total_km
    @total_km ||= activities.sum(&:distance_m) / 1000.0
  end

  def total_km_in_words
    Words.for(total_km.floor)
  end

  def average_km
    total_km / count
  end

  def average_pace
    activities.sum(&:timer_s) / total_km
  end

  def latest
    @all.last
  end

  def days_run
    run_dates.size
  end

  def days_per_week
    days_run / period.weeks
  end

  def pm_count
    activities.count { it.local_started_at.hour >= 12 }
  end

  def pm_percent
    (100.0 * pm_count / count).round
  end

  def streaks
    @streaks ||= Streaks.new(@all.map { it.local_started_at.to_date }, period)
  end

  def bars
    Bars.new(activities, period).data
  end

  def trailing
    Trailing.new(@all, period).data
  end

  def scatter
    Scatter.new(activities).data
  end

  def heatmap
    Heatmap.new(activities, period).data
  end

  def records
    PersonalRecords.for(activities)
  end

  def goal_tiles
    @goal_tiles ||= goal_periods.filter_map { |kind, starts_on|
      goal = Goal.find_by(period: kind, starts_on:)
      GoalSlot.new(goal:, progress: goal.progress(today: @today, activities: @all)) if goal
    }
  end

  def goal_to_create
    kind, starts_on = goal_periods.first
    Goal.new(period: kind, starts_on:) if !period.all_time? && goal_tiles.empty?
  end

  def years(selected = nil)
    ([@today.year, selected] + @all.map { it.local_started_at.year }).compact.uniq.sort.reverse
  end

  def selectable_months(year)
    months = @all.select { it.local_started_at.year == year }.map { it.local_started_at.month }.uniq
    months |= [@today.month] if year == @today.year
    months
  end

  private
  def goal_periods
    case period.kind
    when :all then [["year", @today.beginning_of_year], ["month", @today.beginning_of_month]]
    when :year then [["year", Date.new(period.year, 1, 1)]]
    when :month then [["month", Date.new(period.year, period.month, 1)]]
    end
  end

  def run_dates
    @run_dates ||= activities.map { it.local_started_at.to_date }.uniq
  end
end
