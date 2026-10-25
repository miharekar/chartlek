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
end
