class Overview::Streaks
  Segment = Data.define(:kind, :from, :to) do
    def days
      (to - from).to_i + 1
    end
  end

  def initialize(run_dates, period)
    @run_dates = run_dates.to_set
    @range = [period.first, @run_dates.min].max..period.last
    @includes_today = period.includes_today?
  end

  def longest_streak
    segments.select { it.kind == :streak }.max_by(&:days)
  end

  def longest_break
    segments.select { it.kind == :break }.max_by(&:days)
  end

  def current
    if @includes_today
      last, previous = segments.last(2).reverse

      if last.kind == :break && last.days == 1 && previous
        previous
      else
        last
      end
    end
  end

  private
  def segments
    @segments ||= @range.each_with_object([]) do |date, list|
      kind = @run_dates.include?(date) ? :streak : :break

      if list.last&.kind == kind
        list[-1] = list.last.with(to: date)
      else
        list << Segment.new(kind:, from: date, to: date)
      end
    end
  end
end
