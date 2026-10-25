class Overview::Period
  TRAILING_DAYS = {all: 365, year: 90, month: 7}.freeze
  GRANULARITIES = {all: :month, year: :week, month: :day}.freeze

  attr_reader :year, :month, :today

  def initialize(year:, month:, today:, first_date:)
    @year = year
    @month = month
    @today = today
    @first_date = first_date
  end

  def kind
    if month
      :month
    elsif year
      :year
    else
      :all
    end
  end

  def all_time?
    kind == :all
  end

  def first
    case kind
    when :month then Date.new(year, month, 1)
    when :year then Date.new(year, 1, 1)
    else @first_date || today
    end
  end

  def last
    [calendar_last, today].min
  end

  def range
    first..last
  end

  delegate :cover?, to: :range

  def days
    [(last - first).to_i + 1, 0].max
  end

  def weeks
    days / 7.0
  end

  def includes_today?
    last == today
  end

  def trailing_days
    TRAILING_DAYS.fetch(kind)
  end

  def granularity
    GRANULARITIES.fetch(kind)
  end

  private
  def calendar_last
    case kind
    when :month then Date.new(year, month, 1).end_of_month
    when :year then Date.new(year, 12, 31)
    else today
    end
  end
end
