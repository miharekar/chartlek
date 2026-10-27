class HrZones
  DEFAULT_SHARES = [0.5, 0.6, 0.7, 0.8, 0.9]
  ZONES = 1..5

  attr_reader :floors, :max_hr, :source

  def self.current(profile = Profile.instance)
    stored = profile.hr_zones

    if stored.present? && stored["floors"].present?
      new(floors: stored["floors"], max_hr: stored["max_hr"], source: "garmin")
    else
      max_hr = Activity.maximum(:max_hr)
      new(floors: DEFAULT_SHARES.map { (it * max_hr).round }, max_hr:, source: "default") if max_hr
    end
  end

  def self.for(activity)
    stored = activity.hr_zones

    if stored.present?
      new(floors: stored["floors"], max_hr: stored["max_hr"], source: stored["source"])
    else
      current
    end
  end

  def initialize(floors:, max_hr:, source:)
    @floors = floors
    @max_hr = max_hr
    @source = source
  end

  def zone(bpm)
    floors.rindex { bpm >= it }&.succ if bpm
  end

  def range(zone)
    last = (zone == ZONES.last) ? max_hr : floors[zone] - 1

    floors[zone - 1]..last
  end

  def seconds(data)
    t, hr = data.stringify_keys.values_at("t", "hr")
    totals = Array.new(ZONES.size, 0.0)

    if hr
      (1...t.size).each do |index|
        zone = zone(hr[index])
        totals[zone - 1] += t[index] - t[index - 1] if zone
      end
    end

    totals.map(&:round)
  end

  def bands
    ZONES.map { {zone: it, from: floors[it - 1], to: (floors[it] if it < ZONES.last)} }
  end

  def garmin?
    source == "garmin"
  end

  def default?
    source == "default"
  end

  def estimated?
    source == "estimated"
  end
end
