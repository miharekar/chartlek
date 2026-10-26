module Activity::TrackProcessing
  extend ActiveSupport::Concern

  CLIP_TOLERANCE_S = 2

  def process_original
    recording = Track::Reader.read(original)

    recording = recording.clip(started_at.to_f - CLIP_TOLERANCE_S, timer_s + CLIP_TOLERANCE_S) if source == "garmin"

    recording = recording.with_distance(distance_m)
    recording = recording.without_stops(timer_s) unless source == "garmin"
    metrics = Track::Metrics.new(recording) unless recording.rebuilt?

    transaction do
      (track || build_track).update!(data: recording.data, chart_metrics: metrics&.chart_metrics)
      update!(splits: metrics&.splits, pace_profile: metrics&.pace_profile, pace_variability: metrics&.pace_variability)
    end
  end
end
