require "test_helper"

class Track::RecordingTest < ActiveSupport::TestCase
  def rows(count)
    Array.new(count) { {at: 1000.0 + it, t: it * 2.0, d: it * 10.0} }
  end

  test "clip drops records before the start and past the timer, then rebases" do
    clipped = Track::Recording.new(rows(10)).clip(1002, 6)

    assert_equal [0.0, 2.0, 4.0, 6.0], clipped.rows.pluck(:t)
    assert_equal [0.0, 10.0, 20.0, 30.0], clipped.rows.pluck(:d)
  end

  test "clip counts timer time, so a pause past the summary's elapsed time is kept" do
    paused = Array.new(6) { {at: 1000.0 + it * 10 + (it >= 3 ? 100 : 0), t: it * 10.0, d: it * 40.0} }

    assert_equal 6, Track::Recording.new(paused).clip(1000, 50).size
  end

  test "laps survive clipping, a rebuilt distance and stop removal" do
    laps = [{at: 1000.0, intensity: "warmup"}]
    recording = Track::Recording.new(rows(11), laps:)

    assert_equal laps, recording.clip(1002, 6).laps
    assert_equal laps, recording.with_distance(200.0).laps
    assert_equal laps, recording.without_stops(10).laps
  end

  test "clip leaves a recording without absolute times alone" do
    recording = Track::Recording.new(rows(5).map { it.except(:at) })

    assert_same recording, recording.clip(0, 1)
  end

  test "keeps a sane distance series" do
    recording = Track::Recording.new(rows(11))

    assert_same recording, recording.with_distance(105.0)
    assert_not recording.rebuilt?
  end

  test "rebuilds a distance series that is more than 10% off at constant pace" do
    rebuilt = Track::Recording.new(rows(11)).with_distance(200.0)

    assert_equal 200.0, rebuilt.rows.last[:d]
    assert_equal 100.0, rebuilt.rows[5][:d]
    assert_predicate rebuilt, :rebuilt?
  end

  test "rebuilds a missing distance series" do
    rebuilt = Track::Recording.new(rows(5).map { it.except(:d) }).with_distance(400.0)

    assert_equal [0.0, 100.0, 200.0, 300.0, 400.0], rebuilt.rows.pluck(:d)
  end

  test "carries distance over dropouts and never lets it go backwards" do
    recording = Track::Recording.new([{t: 0.0, d: 0.0}, {t: 1.0, d: 5.0}, {t: 2.0, d: nil}, {t: 3.0, d: 4.0}, {t: 4.0, d: 9.0}])

    assert_equal [0.0, 5.0, 5.0, 5.0, 9.0], recording.rows.pluck(:d)
  end

  test "refuses a recording it cannot build a track from" do
    assert_raises(Track::Error) { Track::Recording.new(rows(1)).with_distance(10.0) }
    assert_raises(Track::Error) { Track::Recording.new([{t: 5.0, d: 0.0}, {t: 5.0, d: 0.0}]).with_distance(10.0) }
  end

  test "data is columnar, rounded and omits series without data" do
    data = Track::Recording.new([
      {t: 0.0, d: 0.0, lat: 46.123456789, lng: 14.987654321, alt: 300.26, hr: 140, cad: 170.0},
      {t: 1.04, d: 3.14159, lat: 46.2, lng: 14.9, alt: 300.0, hr: nil, cad: nil}
    ]).data

    assert_equal [0.0, 1.0], data[:t]
    assert_equal [0.0, 3.1], data[:d]
    assert_equal [46.12346, 46.2], data[:lat]
    assert_equal [14.98765, 14.9], data[:lng]
    assert_equal [300.3, 300.0], data[:alt]
    assert_equal [140, nil], data[:hr]
    assert_equal [170, nil], data[:cad]
  end

  test "data omits empty series" do
    assert_equal %i[t d], Track::Recording.new(rows(3)).data.keys
  end

  test "data keeps at most 2000 points including the first and last" do
    data = Track::Recording.new(rows(5000)).data

    assert_equal 2000, data[:t].size
    assert_equal 0.0, data[:t].first
    assert_equal 9998.0, data[:t].last
    assert_equal 49990.0, data[:d].last
  end

  test "data keeps short recordings whole" do
    assert_equal 2000, Track::Recording.new(rows(2000)).data[:t].size
  end

  test "treats zero cadence and zero heart rate as missing" do
    recording = Track::Recording.new([{t: 0.0, d: 0.0, hr: 0, cad: 0.0}, {t: 1.0, d: 3.0, hr: 140, cad: 170.0}, {t: 2.0, d: 6.0, hr: 0, cad: 0}])

    assert_equal [nil, 140, nil], recording.rows.pluck(:hr)
    assert_equal [nil, 170.0, nil], recording.rows.pluck(:cad)
    assert_equal [nil, 140, nil], recording.data[:hr]
  end

  test "omits cadence entirely when every value is zero" do
    recording = Track::Recording.new(Array.new(3) { {t: it * 1.0, d: it * 3.0, cad: 0.0} })

    assert_not_includes recording.data.keys, :cad
  end

  def stopped(*points)
    Track::Recording.new(points.map { |t, d| {t: t.to_f, d: d.to_f} })
  end

  test "without_stops takes the excess over the timer out of stopped intervals only" do
    recording = stopped([0, 0], [10, 40], [20, 80], [30, 80], [40, 80], [50, 120], [60, 160])

    trimmed = recording.without_stops(50)

    assert_equal 50.0, trimmed.rows.last[:t]
    assert_equal 160.0, trimmed.rows.last[:d]
    assert_equal [0.0, 10.0, 20.0], trimmed.rows.first(3).pluck(:t)
  end

  test "without_stops never removes more than the stops hold" do
    trimmed = stopped([0, 0], [10, 40], [20, 80], [30, 80], [40, 80], [50, 120], [60, 160]).without_stops(10)

    assert_equal 40.0, trimmed.rows.last[:t]
    assert_equal [0.0, 10.0, 20.0, 20.0, 20.0, 30.0, 40.0], trimmed.rows.pluck(:t)
  end

  test "without_stops takes the largest stop first" do
    trimmed = stopped([0, 0], [10, 40], [13, 40], [23, 80], [40, 80]).without_stops(30)

    assert_equal 30.0, trimmed.rows.last[:t]
    assert_equal 13.0, trimmed.rows[2][:t]
    assert_equal 23.0, trimmed.rows[3][:t]
  end

  test "without_stops leaves a recording at or under the timer alone" do
    recording = stopped([0, 0], [10, 40], [20, 40], [30, 80])

    assert_same recording, recording.without_stops(30)
    assert_same recording, recording.without_stops(60)
  end

  test "without_stops leaves a rebuilt distance alone" do
    rebuilt = Track::Recording.new(rows(11)).with_distance(200.0)

    assert_same rebuilt, rebuilt.without_stops(5)
  end

  test "without_stops keeps slow movement" do
    recording = stopped([0, 0], [10, 40], [20, 50], [30, 90])

    assert_equal 30.0, recording.without_stops(20).rows.last[:t]
  end
end
