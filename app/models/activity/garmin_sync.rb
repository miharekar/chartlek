module Activity::GarminSync
  extend ActiveSupport::Concern

  PAGE_SIZE = 100
  MIN_DISTANCE_M = 100
  RUNNING_TYPES = %w[running trail_running treadmill_running indoor_running virtual_run track_running street_running ultra_run obstacle_run]
  INDOOR_TYPES = %w[treadmill_running indoor_running virtual_run]
  UTC = ActiveSupport::TimeZone["UTC"]
  WEATHER_WINDOW = 60.days
  PROCESSING_ATTRIBUTES = %w[started_at timer_s distance_m]

  class_methods do
    def sync_later
      Activity::SyncJob.perform_later
    end

    def sync_now(full: false, &progress)
      profile = Profile.instance
      previous_error = profile.sync_error

      if profile.start_sync
        changes = []
        broadcast_sync_status

        begin
          client = Garmin::Client.new
          profile.update!(settings: client.profile_settings)
          seen = sync_garmin_pages(client, full:, exhaustive: full || profile.resuming_sync?, changes:, &progress)
          sync_garmin_weather
          changes.concat(delete_unseen_garmin_activities(seen)) if full && seen.any?
        rescue Garmin::Client::InvalidKey
          profile.finish_sync(error: Profile::INVALID_KEY_ERROR)
        rescue => error
          profile.finish_sync(error: "Sync failed: #{error.message.truncate(200)}")
        else
          profile.finish_sync
          link_strava_later if profile.strava_connected?
        ensure
          if changes.any? || profile.sync_error != previous_error
            Turbo::StreamsChannel.broadcast_refresh_to(:garmin_sync)
          else
            broadcast_sync_status
          end
        end
      end
    end

    def download_originals(client: Garmin::Client.new)
      report = {attached: 0, processed: 0, formats: Hash.new(0), failed: {}}
      missing = where(source: "garmin").where.missing(:original_attachment).order(:started_at)
      total = missing.count

      missing.each.with_index(1) do |run, index|
        begin
          run.attach_original(client)
          report[:attached] += 1
          report[:formats][run.original_extension] += 1
          run.process_original
          report[:processed] += 1
        rescue => error
          report[:failed][run.id] = "#{error.class}: #{error.message.truncate(200)}"
        end

        yield(done: index, total:) if block_given?
      end

      report
    end

    private
    def broadcast_sync_status
      Turbo::StreamsChannel.broadcast_replace_to(:garmin_sync, target: "sync_status", partial: "syncs/status", locals: {profile: Profile.instance})
    end

    def sync_garmin_pages(client, full:, exhaustive:, changes:)
      seen = []
      start = 0

      loop do
        page = client.activities(start:, limit: PAGE_SIZE)
        known = garmin_known_ids(page)
        synced = page.select { garmin_eligible?(it) }.each { sync_garmin_run(it, client, changes) }

        seen.concat(synced.map { it["activityId"].to_s })
        yield(start:, fetched: page.size, synced: synced.size) if block_given?
        start += PAGE_SIZE

        all_known = page.all? { !garmin_eligible?(it) || known.include?(it["activityId"].to_s) }
        break if full ? page.empty? : (page.size < PAGE_SIZE || (all_known && !exhaustive))
      end

      seen
    end

    def garmin_known_ids(page)
      where(source: "garmin", external_id: page.map { it["activityId"].to_s }).pluck(:external_id)
    end

    def garmin_eligible?(summary)
      RUNNING_TYPES.include?(summary.dig("activityType", "typeKey")) && summary["distance"].to_f >= MIN_DISTANCE_M
    end

    def sync_garmin_run(summary, client, changes)
      activity = find_or_initialize_by(source: "garmin", external_id: summary["activityId"].to_s)
      activity.update!(garmin_attributes(summary))

      changes << summary if activity.saved_changes?
      sync_garmin_original(activity, client)
      Profile.instance.sync_progress
    end

    def sync_garmin_original(activity, client)
      if !activity.original.attached?
        activity.attach_original(client)
        activity.process_original
      elsif activity.track.nil? || (activity.saved_changes.keys & PROCESSING_ATTRIBUTES).any?
        activity.process_original
      end
    rescue => error
      logger.warn("Garmin original skipped for #{activity.external_id}: #{error.class}: #{error.message.truncate(200)}")
    end

    def sync_garmin_weather
      client = OpenMeteo::Client.new

      weatherable.where(weather: nil).where(local_started_at: WEATHER_WINDOW.ago..).find_each do |activity|
        activity.fetch_weather(client)
      rescue => error
        logger.warn("Weather skipped for #{activity.external_id}: #{error.class}: #{error.message.truncate(200)}")
      end
    end

    def delete_unseen_garmin_activities(seen)
      stale = where(source: "garmin").pluck(:external_id) - seen
      where(source: "garmin", external_id: stale).destroy_all
    end

    def garmin_attributes(summary)
      type = summary.dig("activityType", "typeKey")

      {
        started_at: UTC.parse(summary["startTimeGMT"]),
        local_started_at: UTC.parse(summary["startTimeLocal"]),
        name: summary["activityName"],
        activity_type: type,
        indoor: INDOOR_TYPES.include?(type),
        race: summary.dig("eventType", "typeKey") == "race",
        distance_m: summary["distance"],
        timer_s: summary["duration"],
        moving_s: summary["movingDuration"],
        elapsed_s: summary["elapsedDuration"],
        elevation_gain_m: summary["elevationGain"],
        elevation_loss_m: summary["elevationLoss"],
        avg_hr: summary["averageHR"]&.round,
        max_hr: summary["maxHR"]&.round,
        avg_cadence: summary["averageRunningCadenceInStepsPerMinute"],
        max_cadence: summary["maxRunningCadenceInStepsPerMinute"],
        calories: summary["calories"]&.round,
        vo2max: summary["vO2MaxValue"],
        start_lat: summary["startLatitude"],
        start_lng: summary["startLongitude"],
        location_name: summary["locationName"],
        summary:
      }
    end
  end

  def attach_original(client = Garmin::Client.new)
    original.attach(io: StringIO.new(client.download(external_id)), filename: "#{external_id}.zip", content_type: "application/zip")
  end

  def original_extension
    entry = Zip::File.open_buffer(StringIO.new(original.download)).entries.find(&:file?)
    File.extname(entry.name).delete_prefix(".").downcase
  end
end
