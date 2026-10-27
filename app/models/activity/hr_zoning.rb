module Activity::HrZoning
  extend ActiveSupport::Concern

  ESTIMATE_FROM = 100
  SOURCE = Arel.sql("json_extract(hr_zones, '$.source')")

  included do
    scope :zoned_from_fit, -> { where("json_extract(hr_zones, '$.source') = 'fit'") }
    scope :not_zoned_from_fit, -> { where("json_extract(hr_zones, '$.source') IS NOT 'fit'") }
  end

  class_methods do
    def backfill_hr_zones
      joins(:original_attachment).includes(:track).find_each do |activity|
        activity.update_column(:hr_zones, activity.derive_hr_zones(activity.track&.data || {}, sets: []))
      end

      sets = fit_zone_sets
      not_zoned_from_fit.includes(:track).where.associated(:track).find_each do |activity|
        activity.update_column(:hr_zones, activity.derive_hr_zones(activity.track.data, sets:))
      end

      group(SOURCE).count
    end

    def fit_zone_sets
      zoned_from_fit.order(:started_at).pluck(:started_at, :hr_zones)
    end

    def estimate_hr_zones(sets, at)
      index = sets.bsearch_index { |started_at, _| started_at >= at } || sets.size
      nearest = (index < ESTIMATE_FROM) ? sets.first(ESTIMATE_FROM) : sets[index - ESTIMATE_FROM, ESTIMATE_FROM]
      zones = nearest.map(&:last)

      {"floors" => zones.pluck("floors").transpose.map { median(it) }, "max_hr" => median(zones.pluck("max_hr")), "source" => "estimated"} if zones.any?
    end

    private
    def median(values)
      values.sort[values.size / 2]
    end
  end

  def derive_hr_zones(data, sets: nil)
    zones = fit_hr_zones
    zones ||= Activity.estimate_hr_zones(sets || Activity.fit_zone_sets, started_at) if data.stringify_keys.key?("hr")

    if zones
      seconds = zones["seconds"]
      seconds = HrZones.new(floors: zones["floors"], max_hr: zones["max_hr"], source: zones["source"]).seconds(data) unless seconds&.any?(&:positive?)

      zones.merge("seconds" => seconds)
    end
  end

  def predates_fit_zones?
    first = Activity.zoned_from_fit.minimum(:started_at)

    first.nil? || started_at < first
  end

  def fit_hr_zones
    Track::Reader.zones(original)&.merge("source" => "fit")
  end
end
