class Activity::SmashrunImport::Importer
  GARMIN_MARGIN = 10.minutes
  MATCH_WINDOW = 10.minutes

  attr_reader :report

  def initialize(client, io: $stdout)
    @client = client
    @io = io
    @report = Activity::SmashrunImport::Report.new
  end

  def import
    first_garmin = Activity.where(source: "garmin").minimum(:started_at)
    cutoff = first_garmin - GARMIN_MARGIN

    pairs = @client.activities.filter_map { |summary| link(summary, cutoff) }
    pending = pairs.reject { it.first.original.attached? }
    pending.each_with_index { |(activity, summary), index| fetch(activity, summary, index + 1, pending.size) }
    report
  end

  private
  def link(summary, cutoff)
    started_at = Time.iso8601(summary["startDateTimeLocal"])
    local_started_at = Time.iso8601("#{summary["startDateTimeLocal"][0, 19]}Z")

    if started_at >= cutoff
      report.increment(:garmin_era)
      nil
    elsif activity = nearest(local_started_at)
      update(activity, summary)
      report.increment(:matched)
      [activity, summary]
    else
      report.increment(:created)
      [Activity.create!(attributes_for(summary, started_at, local_started_at)), summary]
    end
  end

  def nearest(local_started_at)
    Activity.where(local_started_at: (local_started_at - MATCH_WINDOW)..(local_started_at + MATCH_WINDOW)).min_by { (it.local_started_at - local_started_at).abs }
  end

  def update(activity, summary)
    activity.calories ||= summary["calories"]
    activity.race ||= summary["isRace"] == 1
    activity.save!
  end

  def attributes_for(summary, started_at, local_started_at)
    treadmill = summary["isTreadmill"] == 1

    {
      source: "smashrun",
      external_id: summary["activityId"].to_s,
      started_at:,
      local_started_at:,
      activity_type: treadmill ? "treadmill_running" : "running",
      indoor: treadmill,
      race: summary["isRace"] == 1,
      distance_m: summary["distance"] * 1000,
      timer_s: summary["duration"],
      avg_hr: summary["heartRateAverage"],
      max_hr: summary["heartRateMax"],
      avg_cadence: summary["cadenceAverage"]&.*(2),
      max_cadence: summary["cadenceMax"]&.*(2),
      calories: summary["calories"],
      elevation_gain_m: summary["elevationGain"],
      elevation_loss_m: summary["elevationLoss"],
      start_lat: summary["startLatitude"],
      start_lng: summary["startLongitude"],
      summary:
    }
  end

  def fetch(activity, summary, position, total)
    @io.puts "Fetching #{position}/#{total}: Smashrun #{summary["activityId"]}"
    attach(activity, summary)
    report.increment(:fetched)
    activity.process_original
  rescue => error
    report.fail(activity, "#{error.class}: #{error.message.truncate(200)}")
  end

  def attach(activity, summary)
    body = ActiveSupport::Gzip.compress(@client.activity(summary["activityId"]))
    activity.original.attach(io: StringIO.new(body), filename: "smashrun-#{summary["activityId"]}.json.gz", content_type: "application/gzip")
  end
end
