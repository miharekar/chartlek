class Activity::StravaImport::Report
  COUNTS = {
    imported: "Imported",
    garmin_era: "In Garmin's history",
    already_imported: "Already imported",
    non_run: "Non-run rows",
    too_short: "Too short",
    invalid: "Invalid"
  }

  def initialize
    @counts = Hash.new(0)
  end

  def count(key)
    @counts[key]
  end

  def increment(key)
    @counts[key] += 1
  end

  def to_s
    COUNTS.map { |key, label| "#{label}: #{count(key)}" }.join("\n")
  end
end
