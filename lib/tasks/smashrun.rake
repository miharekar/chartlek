namespace :smashrun do
  desc "Import runs from before your Garmin history from Smashrun, with full recordings"
  task fetch: :environment do
    $stdout.sync = true
    abort "Sync Garmin first (bin/rails activities:sync): Smashrun only fills the years before your Garmin history" unless Activity.exists?(source: "garmin")
    abort "Set SMASHRUN_USERNAME and SMASHRUN_PASSWORD in .env" if ENV["SMASHRUN_USERNAME"].blank? || ENV["SMASHRUN_PASSWORD"].blank?

    puts Activity.import_smashrun(Smashrun::Client.new)
  end
end
