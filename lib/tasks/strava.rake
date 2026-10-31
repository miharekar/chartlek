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

  desc "Subscribe to Strava webhooks, replacing a different subscription (the tunnel must be up): strava:subscribe[https://chartlek-hooks.rekar.eu]"
  task :subscribe, [:host_url] => :environment do |_, args|
    host = URI(args[:host_url].to_s)

    abort "Usage: bin/rails \"strava:subscribe[https://your-public-host]\"" unless host.is_a?(URI::HTTPS) && host.host.present?
    abort "Set STRAVA_CLIENT_ID, STRAVA_SECRET and SECRET_KEY_BASE in .env" unless [ENV["STRAVA_CLIENT_ID"], ENV["STRAVA_SECRET"], Strava::Webhook.token].all?(&:present?)

    client = Strava::Client.new
    callback_url = Strava::Webhook.callback_url(host.host)
    subscriptions = client.subscriptions
    current = subscriptions.find { it["callback_url"] == callback_url }

    if current
      puts "Already subscribed #{current["id"]} on #{host.host}"
    else
      subscriptions.each { client.unsubscribe(it["id"]) }
      subscription = client.subscribe(callback_url:, verify_token: Strava::Webhook.verify_token)

      puts "Subscribed #{subscription["id"]} on #{host.host}"
    end
  rescue Strava::Client::Error => error
    abort error.message
  end

  desc "Delete the Strava webhook subscription"
  task unsubscribe: :environment do
    client = Strava::Client.new
    subscriptions = client.subscriptions
    subscriptions.each { client.unsubscribe(it["id"]) }

    puts "Deleted #{subscriptions.size} subscription#{"s" unless subscriptions.size == 1}"
  rescue Strava::Client::Error => error
    abort error.message
  end
end
