class PrProgress
  COLUMNS = %w[id time distance pace vdot bucket best name race url].freeze
  REFERENCE_DAYS = [30, 60, 90].freeze

  attr_reader :today

  delegate :empty?, to: :@activities

  def self.benchmarks
    @benchmarks ||= PersonalRecords::BENCHMARKS.map { |name, meters| {name:, meters:, table: Vdot.time_table(meters)} }.freeze
  end

  def self.for_all(**options)
    new(Activity.select(Activity.column_names - %w[summary splits weather bands hr_zones]), **options)
  end

  def initialize(activities, today: nil, from: nil, to: nil)
    @activities = activities.sort_by(&:local_started_at)
    @today = today || Activity.today
    @from = parse_date(from)
    @to = parse_date(to)
  end

  def reference_for(days)
    from = today - (days - 1)

    @activities.select { it.vdot && it.local_started_at.to_date >= from }.max_by { [it.vdot, it.local_started_at] }
  end

  def magic_prs
    Magic.for(records)
  end

  def data
    {
      columns: COLUMNS,
      runs: @activities.map { run_row(it) },
      benchmarks: self.class.benchmarks,
      frontier: records.map { frontier_entry(it) },
      references: REFERENCE_DAYS.index_with { reference_for(it)&.id },
      magic: magic_prs.map { {bucket: bucket_index(it.name), target: it.target_s, percent: it.percent.round(2)} },
      first: epoch_ms(@activities.first.local_started_at),
      today: epoch_ms(today.to_time(:utc)),
      window: [epoch_ms(window_start.to_time(:utc)), epoch_ms(window_end.to_time(:utc))]
    }
  end

  private
  def records
    @records ||= PersonalRecords.for(@activities)
  end

  def run_row(activity)
    bucket = PersonalRecords.bucket_for(activity)

    [activity.id, epoch_ms(activity.local_started_at), (activity.distance_m / 1000).round(3), activity.pace.round(1), activity.vdot&.round(2), bucket && bucket_index(bucket.name), bucket&.time_s&.round(2), activity.name, activity.race ? 1 : 0, Rails.application.routes.url_helpers.run_path(activity)]
  end

  def frontier_entry(record)
    {id: record.activity.id, bucket: bucket_index(record.name), time: record.time_s.round(2), pace: record.pace.round(2), date: epoch_ms(record.activity.local_started_at), race: record.race, name: record.activity.name, url: Rails.application.routes.url_helpers.run_path(record.activity)}
  end

  def bucket_index(name)
    PersonalRecords::BENCHMARKS.index { |benchmark, _| benchmark == name }
  end

  def window_start
    @from || (today << 12)
  end

  def window_end
    (@to || today) + 1
  end

  def epoch_ms(time)
    time.to_i * 1000
  end

  def parse_date(value)
    Date.iso8601(value) if value.is_a?(String)
  rescue Date::Error
    nil
  end
end
