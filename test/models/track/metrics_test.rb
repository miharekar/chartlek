require "test_helper"

class Track::MetricsTest < ActiveSupport::TestCase
  setup do
    recording = Track::Smashrun.parse(file_fixture("tracks/smashrun_pause.json").read)
    @metrics = Track::Metrics.new(recording.with_distance(2400.0))
  end

  test "splits per km plus the final partial km" do
    assert_equal [1000.0, 1000.0, 400.0], @metrics.splits.pluck(:distance)
    assert_equal [250.0, 250.0, 100.0], @metrics.splits.pluck(:time)
    assert_equal [250.0, 250.0, 250.0], @metrics.splits.pluck(:pace)
  end

  test "splits average heart rate and cadence over their own samples" do
    assert_equal [156, 166, 174], @metrics.splits.pluck(:hr)
    assert_equal [170, 170, 170], @metrics.splits.pluck(:cad)
  end

  test "splits sum elevation gain and loss" do
    assert_equal [10.0, 10.0, 4.0], @metrics.splits.pluck(:gain)
    assert_equal [0, 0, 0], @metrics.splits.pluck(:loss)
  end

  test "splits ignore altitude noise under the threshold" do
    altitudes = [500.0, 500.4, 499.8, 500.6, 500.1, 500.9, 500.2, 500.8, 500.0, 500.5, 500.0]
    rows = altitudes.each_with_index.map { |alt, i| {t: i * 100.0, d: i * 100.0, alt:} }
    split = Track::Metrics.new(Track::Recording.new(rows)).splits.first

    assert_equal 0.0, split[:gain]
    assert_equal 0.0, split[:loss]
  end

  test "splits count a climb once it passes the threshold from the last turning point" do
    altitudes = [500.0, 500.6, 501.2, 501.8, 503.0, 502.6, 502.2, 501.8, 501.0, 500.2, 500.0]
    rows = altitudes.each_with_index.map { |alt, i| {t: i * 100.0, d: i * 100.0, alt:} }
    split = Track::Metrics.new(Track::Recording.new(rows)).splits.first

    assert_equal 3.0, split[:gain]
    assert_equal 2.8, split[:loss]
  end

  test "splits count descents as loss" do
    altitudes = [500.0, 503.0, 501.0, 504.0, 500.0, 500.0, 498.0, 499.0, 495.0, 495.0, 490.0]
    rows = altitudes.each_with_index.map { |alt, i| {t: i * 100.0, d: i * 100.0, alt:} }
    split = Track::Metrics.new(Track::Recording.new(rows)).splits.first

    assert_equal 6.0, split[:gain]
    assert_equal 16.0, split[:loss]
    assert_nil split[:hr]
  end

  test "split elevation carries the threshold across km boundaries like the bins" do
    rows = [[0, 100.0], [900, 100.6], [1000, 100.6], [1100, 101.2], [2000, 101.2]].map { |d, alt| {t: d / 4.0, d: d.to_f, alt:} }
    splits = Track::Metrics.new(Track::Recording.new(rows)).splits

    assert_equal [0.0, 1.2], splits.pluck(:gain)
    assert_equal [0.0, 0.0], splits.pluck(:loss)
  end

  test "split elevation is the sum of the 100 m bins of the same km" do
    rows = (0..20).map { |i| {t: i * 25.0, d: i * 100.0, alt: 100.0 + 3 * Math.sin(i)} }
    metrics = Track::Metrics.new(Track::Recording.new(rows))
    bins = metrics.chart_metrics[:elevation]

    assert_equal [bins.first(10).sum { it[:gain] }.round(1), bins.last(10).sum { it[:gain] }.round(1)], metrics.splits.pluck(:gain)
    assert_equal [bins.first(10).sum { it[:loss] }.round(1), bins.last(10).sum { it[:loss] }.round(1)], metrics.splits.pluck(:loss)
  end

  test "split elevation is nil without altitude" do
    rows = [{t: 0.0, d: 0.0}, {t: 250.0, d: 1000.0}]
    split = Track::Metrics.new(Track::Recording.new(rows)).splits.first

    assert_nil split[:gain]
    assert_nil split[:loss]
  end

  test "a final partial km under a meter is dropped" do
    rows = [{t: 0.0, d: 0.0}, {t: 250.0, d: 1000.0}, {t: 250.1, d: 1000.4}]

    assert_equal 1, Track::Metrics.new(Track::Recording.new(rows)).splits.size
  end

  test "pace profile has 20 equal-distance segments" do
    assert_equal Array.new(20) { 250.0 }, @metrics.pace_profile
  end

  test "pace profile follows a changing pace" do
    rows = [{t: 0.0, d: 0.0}, {t: 100.0, d: 500.0}, {t: 300.0, d: 1000.0}]
    profile = Track::Metrics.new(Track::Recording.new(rows)).pace_profile

    assert_equal [200.0] * 10 + [400.0] * 10, profile
  end

  test "pace variability is zero at a constant pace" do
    assert_equal 0.0, @metrics.pace_variability
  end

  test "pace variability is mean absolute deviation over mean of 10 s windows" do
    rows = [0, 20, 80, 100, 160].each_with_index.map { |d, i| {t: i * 10.0, d: d.to_f} }

    metrics = Track::Metrics.new(Track::Recording.new(rows))
    assert_equal 50.0, metrics.pace_variability
    assert_equal [20, 60, 20, 60], metrics.speed_windows
  end

  test "speed windows include timer-running stops and exclude the partial final window" do
    rows = [{t: 0.0, d: 0.0}, {t: 10.0, d: 0.0}, {t: 20.0, d: 40.0}, {t: 25.0, d: 100.0}]
    metrics = Track::Metrics.new(Track::Recording.new(rows))

    assert_equal [0, 40], metrics.speed_windows
    assert_equal 100, metrics.pace_variability
  end

  test "sparse samples retain the existing linear interpolation" do
    metrics = Track::Metrics.new(Track::Recording.new([{t: 0.0, d: 0.0}, {t: 25.0, d: 100.0}]))

    assert_equal [40, 40], metrics.speed_windows
    assert_equal 0, metrics.pace_variability
  end

  test "pace variability needs at least two windows" do
    rows = [{t: 0.0, d: 0.0}, {t: 15.0, d: 30.0}]

    assert_nil Track::Metrics.new(Track::Recording.new(rows)).pace_variability
    assert_nil Track::Metrics.new(Track::Recording.new(rows)).speed_windows
  end

  test "split cadence ignores the zero cadence of a stop" do
    rows = [{t: 0.0, d: 0.0, cad: 0.0}, {t: 100.0, d: 250.0, cad: 170.0}, {t: 200.0, d: 500.0, cad: 0.0}, {t: 300.0, d: 750.0, cad: 180.0}]
    split = Track::Metrics.new(Track::Recording.new(rows)).splits.first

    assert_equal 175, split[:cad]
  end
end
