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
        activity.update_column(:hr_zones, activity.derive_hr_zones(activity.track&.data || {}, reference: nil))
      end

      reference = estimated_hr_zones_reference
      not_zoned_from_fit.includes(:track).where.associated(:track).find_each do |activity|
        activity.update_column(:hr_zones, activity.derive_hr_zones(activity.track.data, reference:))
      end

      group(SOURCE).count
    end

    def estimated_hr_zones_reference
      sets = zoned_from_fit.order(:started_at).limit(ESTIMATE_FROM).pluck(:hr_zones)

      {"floors" => sets.map { it["floors"] }.transpose.map { median(it) }, "max_hr" => median(sets.pluck("max_hr")), "source" => "estimated"} if sets.any?
    end

    private
    def median(values)
      values.sort[values.size / 2]
    end
  end

  def derive_hr_zones(data, reference: Activity.estimated_hr_zones_reference)
    zones = fit_hr_zones || (reference if data.stringify_keys.key?("hr"))

    if zones
      seconds = zones["seconds"]
      seconds = HrZones.new(floors: zones["floors"], max_hr: zones["max_hr"], source: zones["source"]).seconds(data) unless seconds&.any?(&:positive?)

      zones.merge("seconds" => seconds)
    end
  end

  def fit_hr_zones
    Track::Reader.zones(original)&.merge("source" => "fit")
  end
end
