namespace :wellness do
  desc "Backfill Garmin wellness data from the first run, newest first (DAYS=30 limits how far back)"
  task backfill: :environment do
    $stdout.sync = true
    first_run = Activity.minimum(:local_started_at)
    abort "No runs yet; sync first" unless first_run

    from = first_run.to_date
    from = [from, Date.current - ENV["DAYS"].to_i + 1].max if ENV["DAYS"].present?

    sync = Wellness::Sync.new
    report = sync.backfill(from:)

    report.each { |metric, days| puts "#{metric}: #{days} days with data" }
    puts "#{WellnessDay.count} wellness days stored, #{sync.request_count} requests, HR zones from #{HrZones.current&.source || "nowhere (no runs with heart rate)"}"
  end
end
