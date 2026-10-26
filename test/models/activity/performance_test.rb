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
end
