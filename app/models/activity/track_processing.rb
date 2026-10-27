module Activity::TrackProcessing
  extend ActiveSupport::Concern

  CLIP_TOLERANCE_S = 2

  class_methods do
    def backfill_bands
      zones = HrZones.current

      where.not(splits: nil).includes(:track).where.associated(:track).find_each.count { it.update_column(:bands, Track::Bands.new(it.track.data, zones).to_h) }
    end
  end

  def process_original
    recording = Track::Reader.read(original)

    recording = recording.clip(started_at.to_f - CLIP_TOLERANCE_S, timer_s + CLIP_TOLERANCE_S) if source == "garmin"

    recording = recording.with_distance(distance_m)
    recording = recording.without_stops(timer_s) unless source == "garmin"
    metrics = Track::Metrics.new(recording) unless recording.rebuilt?
    bands = Track::Bands.new(recording.data, HrZones.current).to_h unless recording.rebuilt?

    transaction do
      (track || build_track).update!(data: recording.data, chart_metrics: metrics&.chart_metrics)
      update!(splits: metrics&.splits, pace_variability: metrics&.pace_variability, bands:)
    end
  end
end
