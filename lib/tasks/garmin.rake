namespace :garmin do
  desc "Read-only probe of the Garmin wellness endpoints: prints statuses and JSON shapes, never values"
  task probe: :environment do
    $stdout.sync = true

    first_run = Activity.minimum(:local_started_at)
    abort "No runs yet; sync first" unless first_run

    path = ENV.fetch("OUTPUT") { File.join(Dir.tmpdir, "smashback-garmin-probe", "probe.txt") }
    Garmin::Probe.new(client: Garmin::Client.new, first_run_on: first_run.to_date, path:).run
    puts "Also written to #{path}"
  end
end
