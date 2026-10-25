class Activity::SmashrunImport::Report
  COUNTS = {
    matched: "Matched",
    created: "Created",
    garmin_era: "In Garmin's history",
    fetched: "Details fetched"
  }

  attr_reader :failures

  def initialize
    @counts = Hash.new(0)
    @failures = []
  end

  def count(key)
    @counts[key]
  end

  def increment(key)
    @counts[key] += 1
  end

  def fail(activity, reason)
    failures << [activity.id, reason]
  end

  def to_s
    lines = COUNTS.map { |key, label| "#{label}: #{count(key)}" }
    lines << "Failed: #{failures.size}"
    lines += failures.map { |id, reason| "  run #{id}: #{reason}" }
    lines.join("\n")
  end
end
