require "test_helper"

class Activity::PerformanceTest < ActiveSupport::TestCase
  test "saving assigns vdot" do
    activity = create(:activity, distance_m: 10_000, timer_s: 3000)

    assert_equal Vdot.for(10_000, 3000), activity.vdot
  end

  test "saving recomputes when distance or time change" do
    activity = create(:activity, distance_m: 10_000, timer_s: 3000)

    activity.update!(timer_s: 2800)

    assert_equal Vdot.for(10_000, 2800), activity.reload.vdot
  end

  test "vdot stays nil under 400 m" do
    activity = create(:activity, distance_m: 300, timer_s: 90)

    assert_nil activity.vdot
  end

  test "resaving every activity backfills rows saved before the callback existed" do
    Activity.skip_callback(:save, :before, :assign_performance)
    activity = create(:activity, distance_m: 10_000, timer_s: 3000)
    Activity.set_callback(:save, :before, :assign_performance)

    assert_nil activity.vdot

    Activity.find_each(&:save!)

    assert_equal Vdot.for(10_000, 3000), activity.reload.vdot
  end

  test "paused? needs at least 60 seconds between elapsed and timer" do
    assert build(:activity, timer_s: 3000, elapsed_s: 3060).paused?
    assert_not build(:activity, timer_s: 3000, elapsed_s: 3059.9).paused?
    assert_not build(:activity, timer_s: 3000, elapsed_s: nil).paused?
  end

  test "pace is seconds per km from the timer" do
    assert_in_delta 300, build(:activity, distance_m: 10_000, timer_s: 3000, elapsed_s: 3500).pace, 1e-9
  end

  test "hill difficulty matches Smashrun's on public calibration runs" do
    [
      [42_195, 137, 2], [42_165, 270, 2], [1672, 7, 2], [280, 14, 5], [790, 1, 1], [740, 2, 2], [940, 33, 5], [800, 5, 2],
      [850, 3, 2], [1680, 7, 2], [1360, 7, 2], [1740, 6, 2], [1630, 3, 2], [1630, 38, 4], [1890, 7, 2], [1920, 8, 2]
    ].each do |distance_m, gain_m, difficulty|
      assert_equal difficulty, build(:activity, distance_m:, elevation_gain_m: gain_m).hill_difficulty, "#{distance_m} m, #{gain_m} m gain"
    end
  end

  test "hill difficulty is 1 on the flat, capped at 5 and nil without elevation" do
    assert_equal 1, build(:activity, distance_m: 10_000, elevation_gain_m: 0).hill_difficulty
    assert_equal 1, build(:activity, distance_m: 10_000, elevation_gain_m: 14).hill_difficulty
    assert_equal 2, build(:activity, distance_m: 10_000, elevation_gain_m: 15).hill_difficulty
    assert_equal 5, build(:activity, distance_m: 10_000, elevation_gain_m: 900).hill_difficulty
    assert_nil build(:activity, distance_m: 10_000, elevation_gain_m: nil).hill_difficulty
  end

  test "performance zone is the zone of the 5K pace at this vdot" do
    activity = build(:activity, vdot: Vdot.for(5000, 1500))

    assert_equal PaceZones.zone_for(5.0 / Vdot.time_for(5000, activity.vdot) * 3600), activity.performance_zone
    assert_equal 14, activity.performance_zone
  end

  test "performance zone is nil without a vdot" do
    assert_nil build(:activity, vdot: nil).performance_zone
  end

  test "performance zone range spans the history's 25th percentile to its best, padded" do
    create(:activity, distance_m: 5000, timer_s: 1500)
    best = create(:activity, distance_m: 5000, timer_s: 1200)
    easy = create(:activity, distance_m: 5000, timer_s: 1800)

    range = easy.performance_zone_range

    assert_equal easy.performance_zone - 1, range.begin
    assert_equal best.performance_zone + 1, range.end
    assert_nil build(:activity, vdot: nil).performance_zone_range
  end
end
