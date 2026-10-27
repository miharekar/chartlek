require "test_helper"

class Track::FitZonesTest < ActiveSupport::TestCase
  FLOORS = [100, 120, 140, 160, 180, 200]
  SECONDS = [5, 60, 180, 360, 30, 0, 0].map { it * 1000 }

  def zone_message(type: 18, floors: FLOORS, seconds: SECONDS)
    [0x00, type].pack("Cv") + seconds.pack("V7") + floors.pack("C6")
  end

  def fit(*messages, definition: true)
    fields = [0, 2, 4, 2, 28, 6, 6, 6, 2].pack("C*")
    body = (definition ? [0x40, 0, 0].pack("C3") + [216].pack("v") + [3].pack("C") + fields : "") + messages.join
    [12, 0x20, 0, body.bytesize].pack("CCvV") + ".FIT" + body + [0].pack("v")
  end

  test "reads the session's floors, top and zone seconds" do
    zones = Track::FitZones.read(fit(zone_message))

    assert_equal [100, 120, 140, 160, 180], zones["floors"]
    assert_equal 200, zones["max_hr"]
    assert_equal [60, 180, 360, 30, 0], zones["seconds"]
  end

  test "ignores the per-lap messages" do
    lap = zone_message(type: 19, floors: [90, 110, 130, 150, 170, 190])

    assert_equal [100, 120, 140, 160, 180], Track::FitZones.read(fit(lap, zone_message))["floors"]
    assert_nil Track::FitZones.read(fit(lap))
  end

  test "rejects boundaries that do not rise and undefined values" do
    assert_nil Track::FitZones.read(fit(zone_message(floors: [100, 100, 140, 160, 180, 200])))
    assert_nil Track::FitZones.read(fit(zone_message(floors: [100, 120, 140, 160, 255, 255])))
    assert_nil Track::FitZones.read(fit(zone_message(seconds: SECONDS.take(6) + [0xFFFFFFFF])))
  end

  test "keeps the floors of a zone set with no time in any zone" do
    zones = Track::FitZones.read(fit(zone_message(seconds: [5000, 0, 0, 0, 0, 0, 0])))

    assert_equal [100, 120, 140, 160, 180], zones["floors"]
    assert_equal [0, 0, 0, 0, 0], zones["seconds"]
  end

  test "is nil for a file without the message, a truncated file and a file that is not FIT" do
    assert_nil Track::FitZones.read(File.binread(file_fixture("tracks/run.fit")))
    whole = fit(zone_message)
    (0...whole.bytesize - 2).each { assert_nil Track::FitZones.read(whole.byteslice(0, it)), "cut at #{it}" }
    assert_nil Track::FitZones.read("")
    assert_nil Track::FitZones.read("not a fit file")
  end
end
