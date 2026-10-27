class Goal < ApplicationRecord
  PERIODS = %w[month year].freeze

  validates :period, inclusion: {in: PERIODS}
  validates :starts_on, presence: true, uniqueness: {scope: :period}
  validates :distance_m, numericality: {greater_than: 0, less_than: 100_000_000}

  before_validation :snap_starts_on

  def self.start_for(period, date)
    if period == "year"
      date.beginning_of_year
    else
      date.beginning_of_month
    end
  end

  def self.listed
    order(starts_on: :desc, period: :desc)
  end

  def distance_km
    distance_m && distance_m / 1000.0
  end

  def distance_km=(km)
    value = Float(km.to_s, exception: false)
    self.distance_m = value && value * 1000
  end

  def ends_on
    if period == "year"
      starts_on.end_of_year
    else
      starts_on.end_of_month
    end
  end

  def days
    (ends_on - starts_on).to_i + 1
  end

  def title
    if period == "year"
      starts_on.strftime("%Y")
    else
      starts_on.strftime("%B %Y")
    end
  end

  def progress(today: Activity.today, activities: nil)
    from = [starts_on, today - Progress::RECENT_DAYS + 1].min
    activities ||= Activity.where(local_started_at: from.beginning_of_day..ends_on.end_of_day).select(:id, :local_started_at, :distance_m)

    Progress.new(self, activities, today:)
  end

  private
  def snap_starts_on
    self.starts_on = self.class.start_for(period, starts_on) if starts_on && PERIODS.include?(period)
  end
end
