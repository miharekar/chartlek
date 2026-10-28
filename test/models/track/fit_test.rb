require "test_helper"

class Track::FitTest < ActiveSupport::TestCase
  setup { @rows = Track::Fit.parse(file_fixture("tracks/run.fit").binread).rows }

  test "reads every record in the shared shape" do
    assert_equal 40, @rows.size
    assert_in_delta 46.0, @rows.first[:lat], 0.001
    assert_in_delta 14.0, @rows.first[:lng], 0.001
    assert_equal 300.0, @rows.first[:alt]
    assert_equal 140, @rows.first[:hr]
    assert_in_delta 1560.0, @rows.last[:d], 0.1
  end

  test "doubles cadence to both legs" do
    assert_equal 161.0, @rows.first[:cad]
  end

  test "removes the pause from timer time" do
    assert_equal 190.0, @rows[19][:t]
    assert_equal 200.0, @rows[20][:t]
    assert_equal 390.0, @rows.last[:t]
    assert_equal 490.0, @rows.last[:at] - @rows.first[:at]
  end

  def fit_time(offset = 0)
    Time.utc(2024, 3, 5, 6, 30).to_i - Track::Fit::EPOCH + offset
  end

  def record(offset, **fields)
    [20, {253 => [FitBuilder::UINT32, fit_time(offset)], 5 => [FitBuilder::UINT32, offset * 400]}.merge(fields)]
  end

  def lap(offset, intensity)
    [19, {2 => [FitBuilder::UINT32, fit_time(offset)], 23 => [FitBuilder::ENUM, intensity]}]
  end

  test "reads lap starts and intensities" do
    bytes = FitBuilder.bytes([*Array.new(6) { record(it * 10) }, lap(0, 2), lap(20, 3)])
    start = Time.utc(2024, 3, 5, 6, 30).to_f

    assert_equal [[start, 2], [start + 20, 3]], Track::Fit.parse(bytes).laps.map { [it[:at], it[:intensity]] }
  end

  test "scales the raw fields" do
    row = Track::Fit.parse(FitBuilder.bytes([record(0, 78 => [FitBuilder::UINT32, 2750], 4 => [FitBuilder::UINT8, 80], 53 => [FitBuilder::UINT8, 64]), record(10)])).rows.first

    assert_equal 50.0, row[:alt]
    assert_equal 161.0, row[:cad]
    assert_equal 0.0, row[:d]
  end

  test "rejects a record without a timestamp" do
    bytes = FitBuilder.bytes([[20, {5 => [FitBuilder::UINT32, 100]}]])

    assert_raises(Track::Error) { Track::Fit.parse(bytes) }
  end

  test "rejects a record whose timestamp is an array" do
    bytes = FitBuilder.bytes([[20, {253 => [FitBuilder::UINT32, [fit_time, fit_time + 1]]}]])

    assert_raises(Track::Error) { Track::Fit.parse(bytes) }
  end

  test "rejects a file without records" do
    assert_raises(Track::Error) { Track::Fit.parse(FitBuilder.bytes([lap(0, 2)])) }
  end

  test "rejects a file that is not FIT" do
    assert_raises(Track::Error) { Track::Fit.parse("not a fit file") }
  end
end
