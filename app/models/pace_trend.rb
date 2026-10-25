class PaceTrend
  METRICS = %w[spi vdot].freeze
  DISTANCES = [["5K", 5000], ["10K", 10_000], ["Half", 21_097.5], ["Marathon", 42_195]].freeze
  DEFAULT_DISTANCE = "Marathon"
  DEFAULT_WINDOW = 1.year
  COLUMNS = %i[id source external_id local_started_at name distance_m timer_s elapsed_s spi vdot].freeze

  class << self
    def tables(metric)
      @tables ||= {}
      @tables[metric] ||= DISTANCES.map { |label, distance_m| {label:, table: metric_class(metric).time_table(distance_m)} }
    end

    private
    def metric_class(metric)
      metric == "vdot" ? Vdot : Spi
    end
  end

  attr_reader :metric, :distance

  def initialize(metric: nil, exclude_paused: false, exclude_indoor: false, races_only: false, from: nil, to: nil, distance: nil)
    @metric = METRICS.include?(metric) ? metric : "spi"
    @exclude_paused = exclude_paused
    @exclude_indoor = exclude_indoor
    @races_only = races_only
    @from = parse_date(from)
    @to = parse_date(to)
    @distance = DISTANCES.map(&:first).include?(distance) ? distance : DEFAULT_DISTANCE
  end

  def runs
    @runs ||= filtered_runs
  end

  def top_ids
    @top_ids ||= TopRuns.new(runs, metric).ids
  end

  def payload
    {
      metric:,
      distance:,
      runs: runs.map { run_payload(it) },
      tables: self.class.tables(metric),
      domain: [to_ms(runs.first.local_started_at.to_date), to_ms(today)],
      window: [to_ms(window_start), to_ms(window_end)]
    }
  end

  private
  def filtered_runs
    scope = Activity.where.not(metric => nil).select(COLUMNS).order(:local_started_at, :id)
    scope = scope.where(indoor: false) if @exclude_indoor
    scope = scope.where(race: true) if @races_only
    @exclude_paused ? scope.reject(&:paused?) : scope.to_a
  end

  def run_payload(run)
    {
      id: run.id,
      t: run.local_started_at.to_i * 1000,
      name: run.name,
      spi: run.spi&.round(1),
      vdot: run.vdot&.round(2),
      km: (run.distance_m / 1000).round(3),
      s: run.timer_s.round(1),
      top: top_ids.include?(run.id),
      url: run.external_url
    }
  end

  def window_start
    @from || (today - DEFAULT_WINDOW)
  end

  def window_end
    @to ? @to + 1 : today + 1
  end

  def today
    @today ||= Activity.today
  end

  def to_ms(date)
    date.in_time_zone("UTC").to_i * 1000
  end

  def parse_date(value)
    Date.iso8601(value) if value.is_a?(String)
  rescue Date::Error
    nil
  end
end
