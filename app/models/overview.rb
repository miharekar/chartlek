class Overview
  attr_reader :period, :activities

  def self.for(year: nil, month: nil)
    new(Activity.select(Activity.column_names - %w[summary splits weather]), year:, month:)
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

  def longest
    activities.max_by(&:distance_m)
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

  def years(selected = nil)
    ([@today.year, selected] + @all.map { it.local_started_at.year }).compact.uniq.sort.reverse
  end

  def months_with_runs(year)
    @all.select { it.local_started_at.year == year }.map { it.local_started_at.month }.uniq
  end

  private
  def run_dates
    @run_dates ||= activities.map { it.local_started_at.to_date }.uniq
  end
end
