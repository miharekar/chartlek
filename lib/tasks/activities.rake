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
end
