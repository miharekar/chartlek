require "test_helper"

class PaceTrend::TopRunsTest < ActiveSupport::TestCase
  test "keeps the top three of a rolling 30 day window" do
    runs = [500, 400, 300, 200].each_with_index.map { |vdot, day| build_run(vdot, day) }

    assert_equal runs.first(3).map(&:id).to_set, PaceTrend::TopRuns.new(runs).ids
  end

  test "window starts 29 days before the run" do
    strong = [900, 800, 700].each_with_index.map { |vdot, day| build_run(vdot, day) }
    inside = build_run(50, 29)
    outside = build_run(100, 30)

    ids = PaceTrend::TopRuns.new(strong + [inside, outside]).ids

    assert_not_includes ids, inside.id
    assert_includes ids, outside.id
  end

  test "a run drops out once three better runs are within 29 days" do
    runs = [700, 600, 500, 100].each_with_index.map { |vdot, day| build_run(vdot, day) }
    ids = PaceTrend::TopRuns.new(runs).ids

    assert_not_includes ids, runs.last.id
    assert_equal 3, ids.size
  end

  test "ties go to the earlier run, then the lower id" do
    first = build_run(500, 0, id: 2)
    second = build_run(500, 1, id: 1)
    same_time_high = build_run(500, 2, id: 4)
    same_time_low = build_run(500, 2, id: 3)

    ids = PaceTrend::TopRuns.new([same_time_high, second, same_time_low, first]).ids

    assert_equal [first, second, same_time_low].map(&:id).to_set, ids
  end

  test "empty runs have no top runs" do
    assert_empty PaceTrend::TopRuns.new([]).ids
  end

  private
  def build_run(vdot, day, id: nil)
    @next_id = (@next_id || 100) + 1
    Struct.new(:id, :local_started_at, :vdot).new(id || @next_id, Time.utc(2024, 1, 1, 7) + day.days, vdot)
  end
end
