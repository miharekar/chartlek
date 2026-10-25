namespace :strava do
  garmin_first = "Sync Garmin first (bin/rails activities:sync): Strava only fills the years before your Garmin history"

  desc "Import runs from before your Garmin history from an unzipped Strava archive: strava:import[/path/to/archive]"
  task :import, [:path] => :environment do |_, args|
    path = File.expand_path(args[:path].to_s)

    abort garmin_first unless Activity.exists?(source: "garmin")
    abort "No activities.csv in #{path}. Usage: bin/rails \"strava:import[/path/to/archive]\"" unless File.exist?(File.join(path, "activities.csv"))

    puts Activity.import_strava(path)
  end

  desc "Authorize on Strava in the browser, then import runs from before your Garmin history"
  task fetch: :environment do
    $stdout.sync = true
    abort garmin_first unless Activity.exists?(source: "garmin")
    abort "Set STRAVA_CLIENT_ID and STRAVA_SECRET in .env" if ENV["STRAVA_CLIENT_ID"].blank? || ENV["STRAVA_SECRET"].blank?

    client = Strava::Client.new
    callback = Strava::Callback.new
    state = SecureRandom.hex(16)
    puts "Open this link on this machine and authorize Smashback:", client.authorize_url(callback.redirect_uri, state:)

    params = callback.wait
    abort "Strava authorization failed: #{params["error"] || "state mismatch"}" unless params["code"].present? && params["state"] == state
    warn "Private activities were not shared, so they are skipped." unless params["scope"].to_s.split(",").include?("activity:read_all")

    client.authorize(params["code"])
    summaries = client.activities
    puts "Fetched #{summaries.size} Strava activities"
    puts Activity.import_strava_activities(summaries)
  end
end
