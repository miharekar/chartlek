class PaceTrend::TopRuns
  RANK = 3
  WINDOW_DAYS = 30

  def initialize(runs, metric)
    @runs = runs.sort_by { [it.local_started_at, it.id] }
    @metric = metric
  end

  def ids
    @ids ||= @runs.each_index.select { top?(it) }.map { @runs[it].id }.to_set
  end

  private
  def top?(index)
    contenders = keys[first_index(dates[index] - WINDOW_DAYS + 1)...first_index(dates[index] + 1)]
    contenders.count { (it <=> keys[index]) < 0 } < RANK
  end

  def first_index(date)
    dates.bsearch_index { it >= date } || dates.size
  end

  def dates
    @dates ||= @runs.map { it.local_started_at.to_date }
  end

  def keys
    @keys ||= @runs.map { [-it.public_send(@metric), it.local_started_at.to_i, it.id] }
  end
end
