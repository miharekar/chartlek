require "test_helper"

class Track::StepsTest < ActiveSupport::TestCase
  def recording(laps, count: 101)
    rows = Array.new(count) { {at: 1000.0 + it, t: it * 1.0, d: it * 4.0} }
    Track::Recording.new(rows, laps:)
  end

  def lap(offset, intensity)
    {at: 1000.0 + offset, intensity:}
  end

  test "maps lap intensities to steps with distances and times from the track" do
    laps = [lap(0, "warmup"), lap(20, "Undocumented value 5"), lap(40, "Undocumented value 4"), lap(60, "Undocumented value 5"), lap(80, "rest")]

    steps = Track::Steps.new(recording(laps)).to_a

    assert_equal %w[warmup active recovery active rest], steps.pluck(:type)
    assert_equal [[0.0, 80.0], [80.0, 160.0], [160.0, 240.0], [240.0, 320.0], [320.0, 400.0]], steps.map { [it[:from], it[:to]] }
    assert_equal [20.0] * 5, steps.pluck(:time)
  end

  test "merges a trailing cool-down lap into the cool-down but keeps repeated reps apart" do
    laps = [lap(0, "Undocumented value 5"), lap(30, "Undocumented value 5"), lap(60, "cooldown"), lap(90, "cooldown")]

    steps = Track::Steps.new(recording(laps)).to_a

    assert_equal %w[active active cooldown], steps.pluck(:type)
    assert_equal [240.0, 400.0, 40.0], steps.last.values_at(:from, :to, :time)
  end

  test "steps start at zero when the first lap begins before the clipped recording" do
    steps = Track::Steps.new(recording([lap(-30, "warmup"), lap(50, "cooldown")])).to_a

    assert_equal [0.0, 200.0], [steps.first[:from], steps.first[:to]]
  end

  test "drops a lap that starts after the recording ends" do
    steps = Track::Steps.new(recording([lap(0, "warmup"), lap(500, "cooldown")])).to_a

    assert_equal %w[warmup], steps.pluck(:type)
    assert_equal 400.0, steps.first[:to]
  end

  test "has no steps when every lap has the same intensity, as with auto-laps" do
    assert_nil Track::Steps.new(recording([lap(0, "Undocumented value 5"), lap(50, "Undocumented value 5")])).to_a
  end

  test "has no steps without laps, without intensities or with an unknown one" do
    assert_nil Track::Steps.new(recording([])).to_a
    assert_nil Track::Steps.new(recording([lap(0, nil), lap(50, nil)])).to_a
    assert_nil Track::Steps.new(recording([lap(0, "warmup"), lap(50, "Undocumented value 9")])).to_a
  end

  test "has no steps for a recording without absolute times" do
    rows = Array.new(11) { {t: it * 1.0, d: it * 4.0} }

    assert_nil Track::Steps.new(Track::Recording.new(rows, laps: [lap(0, "warmup")])).to_a
  end
end
