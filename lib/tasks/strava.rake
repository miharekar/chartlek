namespace :strava do
  garmin_first = "Sync Garmin first (bin/rails activities:sync): Strava only fills the years before your Garmin history"

  desc "Import runs from before your Garmin history from an unzipped Strava archive: strava:import[/path/to/archive]"
  task :import, [:path] => :environment do |_, args|
    path = File.expand_path(args[:path].to_s)

    abort garmin_first unless Activity.exists?(source: "garmin")
    abort "No activities.csv in #{path}. Usage: bin/rails \"strava:import[/path/to/archive]\"" unless File.exist?(File.join(path, "activities.csv"))

    puts Activity.import_strava(path)
  end

  desc "Import runs from before your Garmin history through the connected Strava account"
  task fetch: :environment do
    abort garmin_first unless Activity.exists?(source: "garmin")
    abort "Strava is not connected. Use the Connect Strava button in the app's nav bar." unless Profile.instance.strava_connected?

    begin
      summaries = Strava::Client.new.activities
    rescue Strava::Client::NotConnected
      abort "Strava rejected the stored tokens. Use the Connect Strava button in the app's nav bar."
    end

    puts "Fetched #{summaries.size} Strava activities"
    puts Activity.import_strava_activities(summaries)
  end
end
