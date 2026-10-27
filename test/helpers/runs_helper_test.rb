require "test_helper"

class RunsHelperTest < ActionView::TestCase
  include WidgetsHelper
  test "finishes pair each Pace Trends distance with its time and kilometres" do
    run = build(:activity, distance_m: 10_000, timer_s: 3000)
    run.vdot = Vdot.for(10_000, 3000)

    finishes = run_finishes(run)

    assert_equal %w[5K 10K Half Marathon], finishes.pluck(:label)
    assert_equal [5.0, 10.0, 21.0975, 42.195], finishes.pluck(:km)
    assert_in_delta Vdot.time_for(10_000, run.vdot), finishes.second[:seconds], 1e-9
  end

  test "tags show race, PR and treadmill chips" do
    assert_equal "", run_tags(build(:activity))

    tags = run_tags(build(:activity, race: true, indoor: true, summary: {"pr" => true}))

    assert_match(/race.*PR.*treadmill/m, tags)
  end
end
