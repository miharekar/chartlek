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

  def garmin?
    source == "garmin"
  end
end
