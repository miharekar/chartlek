require "test_helper"

class GearTest < ActiveSupport::TestCase
  def run_for(gear_id, at, km: 10, seconds: 3000, strava_id: nil)
    create(:activity, started_at: at, local_started_at: at, distance_m: km * 1000.0, timer_s: seconds.to_f, strava_gear_id: gear_id, strava_id: strava_id || (rand(1_000_000) + 1))
  end

  test "usage sums distance and time from our runs, most used first" do
    Gear.create!(strava_id: "g1", name: "Synthetic One", brand_name: "Acme", model: "Zoom")
    Gear.create!(strava_id: "g2", name: "Synthetic Two")
    run_for("g1", Time.utc(2026, 10, 1), km: 10, seconds: 3000)
    run_for("g1", Time.utc(2026, 9, 1), km: 5, seconds: 1500)
    run_for("g2", Time.utc(2026, 8, 1), km: 42)

    one, two = Gear.usage

    assert_equal "Synthetic One", one.gear.name
    assert_equal [2, 15.0, 4500.0], [one.runs, one.km, one.seconds]
    assert_equal Time.utc(2026, 10, 1), one.last_used
    assert_equal 1, two.runs
  end

  test "last 12 months ends on the latest run's date" do
    run_for("g1", Time.utc(2026, 10, 1, 7), km: 10)
    run_for("g1", Time.utc(2025, 10, 2, 7), km: 5)
    run_for("g1", Time.utc(2025, 10, 1, 7), km: 7)

    usage = Gear.usage.first

    assert_equal 15.0, usage.recent_km
    assert_equal 22.0, usage.km
  end

  test "a gear id without a row is listed by its id" do
    run_for("g9", Time.utc(2026, 10, 1))

    gear = Gear.usage.first.gear

    assert_not gear.persisted?
    assert_equal "g9", gear.display_name
  end

  test "a gear Strava no longer knows is dead and shows its id" do
    gear = Gear.create!(strava_id: "g0", synced_at: Time.current)

    assert gear.dead?
    assert_equal "g0", gear.display_name
    assert_not Gear.create!(strava_id: "g1", name: "Live", summary: {}, synced_at: Time.current).dead?
  end

  test "unset usage counts linked runs without gear only" do
    run_for(nil, Time.utc(2026, 10, 1), km: 8)
    run_for(nil, Time.utc(2026, 10, 3), km: 2)
    run_for("g1", Time.utc(2026, 10, 4))
    create(:activity, strava_id: nil, strava_gear_id: nil, distance_m: 99_000.0)

    unset = Gear.unset_usage

    assert_equal [2, 10.0], [unset.runs, unset.km]
    assert_equal Time.utc(2026, 10, 3), unset.last_used
  end

  test "unset usage is nil when every linked run has gear" do
    run_for("g1", Time.utc(2026, 10, 1))

    assert_nil Gear.unset_usage
  end

  test "monthly distance fills every month between first and last use" do
    Gear.create!(strava_id: "g1", name: "One")
    Gear.create!(strava_id: "g2", name: "Two", retired: true)
    run_for("g1", Time.utc(2026, 8, 5), km: 10)
    run_for("g1", Time.utc(2026, 10, 5), km: 4)
    run_for("g2", Time.utc(2026, 9, 5), km: 20)

    chart = Gear.monthly(Gear.usage)

    assert_equal %w[2026-08-01 2026-09-01 2026-10-01], chart[:months]
    one = chart[:gears].find { it[:id] == "g1" }
    two = chart[:gears].find { it[:id] == "g2" }
    assert_equal [10.0, 0.0, 4.0], one[:km]
    assert_equal [0.0, 20.0, 0.0], two[:km]
    assert two[:retired]
  end

  test "monthly is empty without gear runs" do
    assert_equal({months: [], gears: []}, Gear.monthly([]))
  end

  test "per-gear distance agrees with Strava's within one percent when only runs used it" do
    Gear.create!(strava_id: "g1", name: "One", summary: {"distance" => 120_400.0}, synced_at: Time.current)
    12.times { |index| run_for("g1", Time.utc(2026, 1, 1) + index.days, km: 10) }

    usage = Gear.usage.first

    assert_in_delta 120_400.0, usage.km * 1000, 1204.0
  end

  test "suggested gear is the most used in the 14 days either side, nearest on ties" do
    target = run_for(nil, Time.utc(2026, 10, 15, 7))
    run_for("g1", Time.utc(2026, 10, 10, 7))
    run_for("g1", Time.utc(2026, 10, 20, 7))
    run_for("g2", Time.utc(2026, 10, 14, 7))
    run_for("g2", Time.utc(2026, 9, 20, 7))

    assert_equal "g1", Activity.suggested_gear([target])[target.id].strava_id
  end

  test "suggestion falls back to the nearest on a tie and is nil with nothing nearby" do
    tied = run_for(nil, Time.utc(2026, 10, 15, 7))
    run_for("g1", Time.utc(2026, 10, 10, 7))
    run_for("g2", Time.utc(2026, 10, 14, 7))
    lonely = run_for(nil, Time.utc(2025, 1, 1, 7))

    suggestions = Activity.suggested_gear([tied, lonely])

    assert_equal "g2", suggestions[tied.id].strava_id
    assert_nil suggestions[lonely.id]
  end

  test "suggestion uses the gear row when it exists" do
    Gear.create!(strava_id: "g1", name: "Known")
    target = run_for(nil, Time.utc(2026, 10, 15, 7))
    run_for("g1", Time.utc(2026, 10, 14, 7))

    assert_equal "Known", Activity.suggested_gear([target])[target.id].display_name
  end

  test "with_gear filters one gear, none, or nothing" do
    set = run_for("g1", Time.utc(2026, 10, 1))
    unset = run_for(nil, Time.utc(2026, 10, 2))
    unlinked = create(:activity, strava_id: nil)

    assert_equal [set], Activity.with_gear("g1").to_a
    assert_equal [unset], Activity.with_gear("none").to_a
    assert_includes Activity.with_gear(nil), unlinked
  end
end
