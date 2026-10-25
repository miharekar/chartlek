class PersonalRecords
  BENCHMARKS = [
    ["1 mi", 1609.344],
    ["3 km", 3000],
    ["5 km", 5000],
    ["4 mi", 6437.376],
    ["5 mi", 8046.72],
    ["10 km", 10000],
    ["15 km", 15000],
    ["10 mi", 16093.44],
    ["20 km", 20000],
    ["Half marathon", 21097.5],
    ["40 km", 40000],
    ["Marathon", 42195],
    ["50 km", 50000],
    ["100 km", 100000]
  ].freeze
  WINDOW_M = 1000

  Bucket = Data.define(:name, :distance_m, :time_s)
  Record = Data.define(:name, :distance_m, :activity, :time_s, :pace, :speed_kmh, :count, :race)

  def self.for(activities)
    new(activities).records
  end

  def self.bucket_for(activity)
    name, distance_m = BENCHMARKS.find { |_, benchmark_m| activity.distance_m >= benchmark_m && activity.distance_m < benchmark_m + WINDOW_M }

    Bucket.new(name:, distance_m:, time_s: activity.timer_s * distance_m / activity.distance_m) if name
  end

  def initialize(activities)
    @activities = activities.to_a
  end

  def records
    BENCHMARKS.filter_map { |name, _| record_for(entries_by_name[name]) }
  end

  private
  def entries_by_name
    @entries_by_name ||= @activities.filter_map { |activity|
      bucket = self.class.bucket_for(activity)
      [activity, bucket] if bucket
    }.group_by { |_, bucket| bucket.name }
  end

  def record_for(entries)
    if entries
      activity, bucket = entries.min_by { |_, bucket| bucket.time_s }
      Record.new(name: bucket.name, distance_m: bucket.distance_m, activity:, time_s: bucket.time_s, pace: bucket.time_s / bucket.distance_m * 1000, speed_kmh: bucket.distance_m / bucket.time_s * 3.6, count: entries.size, race: activity.race)
    end
  end
end
