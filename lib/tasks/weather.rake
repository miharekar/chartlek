namespace :weather do
  desc "Fetch Open-Meteo weather for outdoor runs that don't have it yet"
  task fetch: :environment do
    $stdout.sync = true

    report = Activity.fetch_weather do |progress|
      puts "#{progress[:done]}/#{progress[:total]} runs" if (progress[:done] % 50).zero?
    end

    puts "Fetched #{report[:fetched]}, pending #{report[:pending]} (no data yet), skipped #{report[:skipped]} (indoor or no coordinates), failed #{report[:failed].size}"
    report[:failed].each { |id, reason| puts "  #{id}: #{reason}" }
  end
end
