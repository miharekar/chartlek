namespace :activities do
  run_sync = lambda do |full|
    abort "A sync is already running" if Profile.instance.syncing?

    Activity.sync_now(full:) do |page|
      puts "start #{page[:start]}: #{page[:fetched]} fetched, #{page[:synced]} runs synced"
    end

    error = Profile.instance.sync_error
    abort error if error

    puts "Done: #{Activity.where(source: "garmin").count} Garmin runs"
  end

  desc "Sync new Garmin runs"
  task sync: :environment do
    run_sync.call(false)
  end

  desc "Re-page all Garmin runs and delete local ones that no longer exist on Garmin"
  task resync: :environment do
    run_sync.call(true)
  end

  desc "Rebuild tracks and metrics from every stored original"
  task reprocess: :environment do
    activities = Activity.joins(:original_attachment)
    total = activities.count
    failures = {}

    activities.find_each.with_index(1) do |activity, index|
      activity.process_original
    rescue => error
      failures[activity.id] = "#{activity.source} #{activity.external_id}: #{error.message.truncate(200)}"
    ensure
      puts "#{index}/#{total}" if (index % 50).zero?
    end

    puts "Processed #{total - failures.size} of #{total} runs"
    failures.each { |id, reason| puts "Failed #{id} (#{reason})" }
  end

  desc "Compute training bands from every stored track"
  task bands: :environment do
    puts "Computed bands for #{Activity.backfill_bands} runs"
  end

  desc "Read per-run HR zones from the stored originals and estimate them for older runs"
  task hr_zones: :environment do
    counts = Activity.backfill_hr_zones

    puts "HR zones by source: #{counts.map { |source, count| "#{source || "none"} #{count}" }.join(", ")}"
  end

  desc "Download and process the Garmin original of every run that lacks one"
  task download: :environment do
    report = Activity.download_originals do |progress|
      puts "#{progress[:done]}/#{progress[:total]}" if (progress[:done] % 50).zero?
    end

    puts "Attached #{report[:attached]}, processed #{report[:processed]}"
    puts "Formats: #{report[:formats].map { |format, count| "#{format} #{count}" }.join(", ")}"
    report[:failed].each { |id, reason| puts "Failed #{id} (#{reason})" }
  end
end
