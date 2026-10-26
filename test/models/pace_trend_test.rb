require "test_helper"

class PaceTrendTest < ActiveSupport::TestCase
  test "skips runs without a metric value" do
    create(:activity, distance_m: 300, timer_s: 90)
    run = create(:activity)

    assert_equal [run], PaceTrend.new.runs.to_a
  end

  test "exclude_paused drops runs with pauses" do
    paused = create(:activity, timer_s: 3000, elapsed_s: 3100)
    clean = create(:activity, timer_s: 3000, elapsed_s: 3030)
    unknown = create(:activity, timer_s: 3000, elapsed_s: nil)

    assert_equal [paused, clean, unknown].map(&:id), PaceTrend.new.runs.map(&:id)
    assert_equal [clean, unknown].map(&:id), PaceTrend.new(exclude_paused: true).runs.map(&:id)
  end

  test "exclude_indoor drops indoor runs" do
    create(:activity, indoor: true)
    outdoor = create(:activity)

    assert_equal [outdoor.id], PaceTrend.new(exclude_indoor: true).runs.map(&:id)
  end

  test "races_only keeps races" do
    create(:activity)
    race = create(:activity, race: true)

    assert_equal [race.id], PaceTrend.new(races_only: true).runs.map(&:id)
  end

  test "runs are ordered by local start" do
    later = create(:activity, local_started_at: Time.utc(2024, 5, 1))
    earlier = create(:activity, local_started_at: Time.utc(2024, 4, 1))

    assert_equal [earlier.id, later.id], PaceTrend.new.runs.map(&:id)
  end

  test "top runs follow the metric" do
    runs = [3700, 3800, 3900, 4000].each_with_index.map { |timer_s, day| create(:activity, local_started_at: Time.utc(2024, 1, 1) + day.days, distance_m: 10_000, timer_s:) }

    assert_equal runs.first(3).map(&:id).to_set, PaceTrend.new.top_ids
    assert_equal runs.first(3).map(&:id).to_set, PaceTrend.new(metric: "vdot").top_ids
    assert_equal [true, true, true, false], PaceTrend.new.payload[:runs].pluck(:top)
  end

  test "payload serializes runs" do
    run = create(:activity, name: "Evening <b>Run</b>", local_started_at: Time.utc(2024, 3, 5, 18, 0), distance_m: 10_000, timer_s: 3000)

    payload = PaceTrend.new(metric: "vdot").payload
    row = payload[:runs].first

    assert_equal "vdot", payload[:metric]
    assert_equal run.id, row[:id]
    assert_equal Time.utc(2024, 3, 5, 18).to_i * 1000, row[:t]
    assert_equal "Evening <b>Run</b>", row[:name]
    assert_equal run.spi.round(1), row[:spi]
    assert_equal run.vdot.round(2), row[:vdot]
    assert_equal 10.0, row[:km]
    assert_equal 3000.0, row[:s]
    assert row[:top]
    assert_equal "/runs/#{run.id}", row[:url]
    assert_equal %w[5K 10K Half Marathon], payload[:tables].pluck(:label)
    assert_equal Vdot.time_table(42_195), payload[:tables].last[:table]
  end

  test "payload domain and default window" do
    create(:activity, local_started_at: Time.utc(2020, 6, 15, 7), started_at: Time.utc(2020, 6, 15, 7))

    travel_to Time.utc(2024, 3, 5, 12) do
      payload = PaceTrend.new.payload

      assert_equal [Time.utc(2020, 6, 15).to_i * 1000, Time.utc(2024, 3, 5).to_i * 1000], payload[:domain]
      assert_equal [Time.utc(2023, 3, 5).to_i * 1000, Time.utc(2024, 3, 6).to_i * 1000], payload[:window]
    end
  end

  test "payload honors from, to and distance and ignores junk" do
    create(:activity)

    payload = PaceTrend.new(from: "2023-01-10", to: "2023-02-01", distance: "10K").payload

    assert_equal [Time.utc(2023, 1, 10).to_i * 1000, Time.utc(2023, 2, 2).to_i * 1000], payload[:window]
    assert_equal "10K", payload[:distance]

    junk = PaceTrend.new(metric: "bogus", from: "nope", distance: "far")

    assert_equal "spi", junk.metric
    assert_equal "Marathon", junk.distance
    assert_equal Date.current.in_time_zone("UTC").to_i * 1000 + 1.day.to_i * 1000, junk.payload[:window].last
  end
end
