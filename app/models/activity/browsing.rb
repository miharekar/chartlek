module Activity::Browsing
  extend ActiveSupport::Concern

  SORTS = {
    "date" => "local_started_at",
    "name" => "name COLLATE NOCASE",
    "km" => "distance_m",
    "time" => "timer_s",
    "pace" => "timer_s / distance_m",
    "hr" => "avg_hr",
    "elevation" => "elevation_gain_m",
    "vdot" => "vdot"
  }.freeze
  SIMILAR_DISTANCE = 0.1
  FASTEST_WINDOWS = [90, 180, 365].freeze
  FASTEST_LIMIT = 5
  TRAINING_WINDOW = 90
  YEAR_SQL = Arel.sql("strftime('%Y', local_started_at)")
  MONTH_SQL = Arel.sql("strftime('%m', local_started_at)")
  NOTABLE_COLUMNS = %w[id local_started_at distance_m timer_s elapsed_s elevation_gain_m weather location_name].freeze

  class_methods do
    def listed(year: nil, month: nil, sort: nil, dir: nil)
      scope = in_period(year, month)
      expression = SORTS.fetch(sort, SORTS["date"])
      direction = (dir == "asc") ? "ASC" : "DESC"

      scope.select(column_names - %w[summary splits weather]).order(Arel.sql("#{expression} #{direction} NULLS LAST"), id: :desc)
    end

    def years_with_runs
      group(YEAR_SQL).count.keys.map(&:to_i).sort.reverse
    end

    def months_with_runs(year)
      in_period(year, nil).group(MONTH_SQL).count.keys.map(&:to_i)
    end

    private
    def in_period(year, month)
      if year && month
        where(local_started_at: Time.utc(year, month).all_month)
      elsif year
        where(local_started_at: Time.utc(year).all_year)
      else
        all
      end
    end
  end

  def previous_run
    Activity.where("local_started_at < :at OR (local_started_at = :at AND id < :id)", at: local_started_at, id:).order(local_started_at: :desc, id: :desc).first
  end

  def next_run
    Activity.where("local_started_at > :at OR (local_started_at = :at AND id > :id)", at: local_started_at, id:).order(:local_started_at, :id).first
  end

  def same_day_runs
    Activity.where(local_started_at: local_started_at.all_day).order(:local_started_at, :id)
  end

  def longest_rank
    Activity.where("distance_m > ?", distance_m).count + 1
  end

  def distance_distribution
    Activity.pluck(:distance_m).map { it / 1000.0 }
  end

  def similar_pace_distribution
    similar_distance.pluck(Arel.sql("timer_s / distance_m * 1000"))
  end

  def run_count
    @run_count ||= Activity.count
  end

  def similar_count
    @similar_count ||= similar_distance.count
  end

  def similar_rank
    similar_distance.where("timer_s / distance_m * 1000 < ?", pace).count + 1
  end

  def fastest_similar(days)
    similar_distance
      .where(local_started_at: (local_started_at - days.days)..local_started_at)
      .select(:id, :local_started_at, :name, :distance_m, :timer_s)
      .order(Arel.sql("timer_s / distance_m"), :id)
      .limit(FASTEST_LIMIT)
  end

  def earlier_runs
    Activity.where(local_started_at: ...local_started_at).select(NOTABLE_COLUMNS)
  end

  def prior_training(days = TRAINING_WINDOW)
    window = (local_started_at.beginning_of_day - days.days)...local_started_at
    Activity.where(local_started_at: window).where.not(id:).order(:local_started_at, :id).map do |other|
      {t: other.local_started_at.to_i * 1000, km: (other.distance_m / 1000).round(2), pace: other.pace.round(1), hr: other.avg_hr, vdot: other.vdot&.round(2), s: other.timer_s.round, url: Rails.application.routes.url_helpers.run_path(other)}
    end
  end

  def finish_times
    PaceTrend::DISTANCES.map { |label, meters| [label, Vdot.time_for(meters, vdot)] } if vdot
  end

  private
  def similar_distance
    Activity.where(distance_m: (distance_m * (1 - SIMILAR_DISTANCE))..(distance_m * (1 + SIMILAR_DISTANCE)))
  end
end
