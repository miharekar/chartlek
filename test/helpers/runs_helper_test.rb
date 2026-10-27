require "test_helper"

class RunsHelperTest < ActionView::TestCase
  test "sparkline draws faster paces higher" do
    svg = run_sparkline([300, 240])

    assert_includes svg, "stroke: var(--chart-accent)"
    assert_includes svg, "points=\"0.0,18.0 60.0,2.0\""
  end

  test "sparkline is empty without a profile" do
    assert_nil run_sparkline(nil)
    assert_nil run_sparkline([])
    assert_nil run_sparkline([300])
  end

  test "flat profile does not divide by zero" do
    assert_includes run_sparkline([300, 300]), "polyline"
  end

  test "finishes pair each Pace Trends distance with its time and kilometres" do
    run = build(:activity, distance_m: 10_000, timer_s: 3000)
    run.vdot = Vdot.for(10_000, 3000)

    finishes = run_finishes(run)

    assert_equal %w[5K 10K Half Marathon], finishes.pluck(:label)
    assert_equal [5.0, 10.0, 21.0975, 42.195], finishes.pluck(:km)
    assert_in_delta Vdot.time_for(10_000, run.vdot), finishes.second[:seconds], 1e-9
  end
end
