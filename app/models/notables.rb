class Notables
  WINDOWS = {"in 1 month" => 1, "in 3 months" => 3, "in 6 months" => 6, "in 12 months" => 12, "ever" => nil}.freeze
  SUN_MARGIN_S = 30 * 60
  SIMILAR_DISTANCE = 0.1
  MILESTONE_M = 1_000_000

  def self.for(activity, runs)
    new(activity, runs).all
  end

  def initialize(activity, runs)
    @activity = activity
    @previous = runs.select { it.local_started_at < activity.local_started_at }
  end

  def all
    [longest, fastest, climbing, temperature, sun, moon, location, start_time, streak, first_of_year, milestone, race].flatten.compact
  end

  private
  def longest
    windowed("Longest run", @previous) { it.distance_m < @activity.distance_m }
  end

  def fastest
    similar = @previous.select { it.distance_m.between?(@activity.distance_m * (1 - SIMILAR_DISTANCE), @activity.distance_m * (1 + SIMILAR_DISTANCE)) }

    windowed("Fastest run for a similar distance", similar) { it.pace > @activity.pace }
  end

  def climbing
    windowed("Most elevation gain", @previous) { (it.elevation_gain_m || 0) < @activity.elevation_gain_m } if @activity.elevation_gain_m
  end

  def temperature
    degrees = @activity.weather&.dig("temperature")

    if degrees
      weathered = @previous.select { it.weather&.dig("temperature") }

      [
        windowed("Hottest run", weathered) { it.weather["temperature"] < degrees },
        windowed("Coldest run", weathered) { it.weather["temperature"] > degrees }
      ]
    end
  end

  def sun
    weather = @activity.weather || {}

    %w[sunrise sunset].select { weather[it] && near?(Time.zone.parse(weather[it])) }.map { "Run during #{it}" }
  end

  def moon
    phase = Moon.phase(@activity.local_started_at)

    "Run on a #{phase} moon" if phase
  end

  def location
    name = @activity.location_name

    "First run at #{name}" if name.present? && @previous.none? { it.location_name == name }
  end

  def start_time
    seconds = time_of_day(@activity)

    [
      windowed("Earliest start", @previous) { time_of_day(it) > seconds },
      windowed("Latest start", @previous) { time_of_day(it) < seconds }
    ]
  end

  def streak
    if @previous.any?
      dates = @previous.map { it.local_started_at.to_date }.uniq
      earlier = streaks(dates).longest_streak.days
      current = streaks(dates + [@activity.local_started_at.to_date]).current.days

      "Extends your longest streak to #{current} days" if current > earlier
    end
  end

  def first_of_year
    "First run of the year" if @previous.none? { it.local_started_at.year == @activity.local_started_at.year }
  end

  def milestone
    before = @previous.sum(&:distance_m)
    crossed = ((before + @activity.distance_m) / MILESTONE_M).floor

    "Passed #{ActiveSupport::NumberHelper.number_to_delimited(crossed * 1000)} km lifetime" if crossed > (before / MILESTONE_M).floor
  end

  def race
    "Race" if @activity.race
  end

  def windowed(title, runs, &beaten)
    label, = WINDOWS.reverse_each.find do |_, months|
      scope = within(runs, months)
      scope.any? && scope.all?(&beaten)
    end

    "#{title} #{label}" if label
  end

  def within(runs, months)
    if months
      cutoff = @activity.local_started_at - months.months
      runs.select { it.local_started_at >= cutoff }
    else
      runs
    end
  end

  def near?(time)
    [@activity.local_started_at, @activity.local_started_at + (@activity.elapsed_s || @activity.timer_s)].any? { (it - time).abs <= SUN_MARGIN_S }
  end

  def time_of_day(run)
    @times_of_day ||= {}
    @times_of_day[run.local_started_at] ||= run.local_started_at.seconds_since_midnight
  end

  def streaks(dates)
    Overview::Streaks.new(dates, Overview::Period.new(year: nil, month: nil, today: dates.max, first_date: dates.min))
  end
end
