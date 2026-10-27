class TrainingBands
  CATEGORIES = %w[pace hr grade].freeze
  VIEWS = %w[absolute percent].freeze
  DEFAULT_CATEGORY = "pace"
  DEFAULT_VIEW = "absolute"
  PACE_GROUPS = [["Walk", 0..0], ["Easy", 1..9], ["Steady", 10..13], ["Tempo", 14..17], ["Fast", 18..PaceZones::ZOOM]].freeze
  COLORS = {
    "pace" => Array.new(PaceZones::COUNT) { "var(--pace-zone-#{it})" },
    "hr" => HrZones::ZONES.map { "var(--hr-zone-#{it})" },
    "grade" => Array.new(Track::Bands::GRADE_COUNT) { "var(--grade-#{it})" }
  }.freeze

  attr_reader :view

  def initialize(from: nil, to: nil, category: nil, view: nil)
    @from = parse_date(from)
    @to = parse_date(to)
    @category = category
    @view = VIEWS.include?(view) ? view : DEFAULT_VIEW
  end

  def data?
    rows.any?
  end

  def category
    categories.include?(@category) ? @category : DEFAULT_CATEGORY
  end

  def categories
    @categories ||= rows.any? ? CATEGORIES.select { it == DEFAULT_CATEGORY || matrices.fetch(it).any? } : [DEFAULT_CATEGORY]
  end

  def groups(name)
    group_definitions.fetch(name).map { |label, bands| {label:, bands:} }
  end

  def payload
    {
      start: to_ms(first_week),
      domain: [to_ms(first_week), to_ms(last_day)],
      window: [to_ms(window_from), to_ms(window_to)],
      weeks: week_count,
      category:,
      view:,
      categories: categories.index_with { |name| {groups: groups(name), colors: COLORS.fetch(name), bands: matrices.fetch(name)} }
    }
  end

  private
  def rows
    @rows ||= Activity.where.not(bands: nil).order(:local_started_at).pluck(:local_started_at, :bands)
  end

  def first_week
    @first_week ||= rows.first.first.to_date.beginning_of_week
  end

  def last_day
    @last_day ||= rows.last.first.to_date
  end

  def window_from
    [[@from || first_week, first_week].max, last_day].min
  end

  def window_to
    [[@to || last_day, window_from].max, last_day].min + 1
  end

  def week_count
    @week_count ||= (last_day.beginning_of_week - first_week).to_i / 7 + 1
  end

  def matrices
    @matrices ||= CATEGORIES.index_with do |name|
      sums = Hash.new { |hash, band| hash[band] = Array.new(week_count, 0) }

      rows.each do |started_at, bands|
        week = (started_at.to_date.beginning_of_week - first_week).to_i / 7
        bands[name]&.each_with_index { |seconds, band| sums[band][week] += seconds if seconds.positive? }
      end

      sums.sort.to_h
    end
  end

  def group_definitions
    @group_definitions ||= {
      "pace" => PACE_GROUPS.map { |label, zones| [label, zones.to_a] },
      "hr" => HrZones::ZONES.map { ["Zone #{it}", [it - 1]] },
      "grade" => grade_labels.each_with_index.map { |label, band| [label, [band]] }
    }
  end

  def grade_labels
    edges = Track::Bands::GRADE_EDGES.map { format("%+d", it) }

    ["Below #{edges.first}%", *edges.each_cons(2).map { |from, to| "#{from} to #{to}%" }, "Above #{edges.last}%"]
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
