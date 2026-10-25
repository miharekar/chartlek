FactoryBot.define do
  factory :activity do
    source { "garmin" }
    sequence(:external_id) { "10000#{it}" }
    started_at { Time.utc(2024, 3, 5, 6, 30) }
    local_started_at { Time.utc(2024, 3, 5, 7, 30) }
    name { "Morning Run" }
    activity_type { "running" }
    distance_m { 10_000.0 }
    timer_s { 3000.0 }
  end
end
