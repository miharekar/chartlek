class Overview::Heatmap
  WEEKLY_THRESHOLDS = [1, 20, 40, 50, 60, 80].freeze
  DAILY_THRESHOLDS = [0, 5, 10, 15, 21, 30].freeze
  QUANTILES = [0.25, 0.5, 0.75, 0.9, 0.97].freeze
  MONTH_REFERENCE_YEAR = 2026
  WEEKDAY_LABELS = %w[Mon Tue Wed Thu Fri Sat Sun].freeze

  def self.level(km, thresholds)
    thresholds.count { km > it }
  end

  def initialize(activities, period)
    @activities = activities
    @period = period
  end

  def data
    if @period.all_time?
      weekly
    else
      daily
    end
  end

  private
  def weekly
    totals = week_totals
    mondays = (@period.first.beginning_of_week..@period.last.beginning_of_week).step(7).to_a
    years = mondays.map(&:cwyear).uniq
    alt = alt_thresholds(totals.values.select(&:positive?))

    {
      rows: years.map(&:to_s),
      cols: 53,
      columns: month_columns,
      cells: mondays.map { weekly_cell(it, years, totals[it], alt) },
      thresholds: WEEKLY_THRESHOLDS,
      alt_thresholds: alt,
      unit: "total kilometers run"
    }
  end

  def week_totals
    @activities.each_with_object(Hash.new(0.0)) { |activity, sums| sums[activity.local_started_at.to_date.beginning_of_week] += activity.distance_m / 1000.0 }
  end

  def weekly_cell(monday, years, km, alt)
    middle = monday + 3

    {
      row: years.index(monday.cwyear),
      col: monday.cweek - 1,
      level: self.class.level(km, WEEKLY_THRESHOLDS),
      alt: self.class.level(km, alt),
      tip: ["Week of #{date_text(monday)}", distance_text(km)],
      href: (Rails.application.routes.url_helpers.overview_period_path(middle.year, middle.month) if km.positive?),
      external: false
    }
  end

  def month_columns
    (1..12).map do |month|
      first = Date.new(MONTH_REFERENCE_YEAR, month, 1)
      thursday = first + ((4 - first.wday) % 7)
      {label: first.strftime("%b"), col: thursday.cweek - 1}
    end
  end

  def alt_thresholds(weeks)
    sorted = weeks.sort
    [0] + QUANTILES.map { quantile(sorted, it).round(1) }
  end

  def quantile(sorted, fraction)
    position = (sorted.size - 1) * fraction
    lower = sorted[position.floor]
    upper = sorted[position.ceil]
    lower + (upper - lower) * (position - position.floor)
  end

  def daily
    by_day = @activities.group_by { it.local_started_at.to_date }
    first_monday = @period.first.beginning_of_week

    {
      rows: WEEKDAY_LABELS,
      cols: ((@period.last.beginning_of_week - first_monday).to_i / 7) + 1,
      columns: daily_columns(first_monday),
      cells: @period.range.map { daily_cell(it, by_day[it] || [], first_monday) },
      thresholds: DAILY_THRESHOLDS,
      unit: "kilometers run per day"
    }
  end

  def daily_columns(first_monday)
    @period.range.map(&:beginning_of_month).uniq.map { {label: it.strftime("%b"), col: ([it, @period.first].max.beginning_of_week - first_monday).to_i / 7} }.uniq { it[:col] }
  end

  def daily_cell(date, runs, first_monday)
    km = runs.sum(&:distance_m) / 1000.0

    {
      row: date.cwday - 1,
      col: (date.beginning_of_week - first_monday).to_i / 7,
      level: self.class.level(km, DAILY_THRESHOLDS),
      tip: [date_text(date), (runs.any? ? distance_text(km) : "No run")],
      href: runs.first&.external_url,
      external: true,
      text: (date.day.to_s if @period.kind == :month)
    }
  end

  def date_text(date)
    date.strftime("%-d %b %Y")
  end

  def distance_text(km)
    format("%.1f km", km)
  end
end
