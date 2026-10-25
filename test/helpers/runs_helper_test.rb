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
end
