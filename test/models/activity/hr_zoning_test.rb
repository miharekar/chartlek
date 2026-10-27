require "test_helper"

class Activity::HrZoningTest < ActiveSupport::TestCase
  FLOORS = [100, 120, 140, 160, 180]

  def crc16(bytes)
    table = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, 0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]

    bytes.each_byte.reduce(0) do |crc, byte|
      [byte & 0xF, byte >> 4].reduce(crc) { |sum, nibble| (sum >> 4) ^ table[sum & 0xF] ^ table[nibble] }
    end
  end

  def fit(with_zones:, seconds: [0, 60, 180, 360, 0, 0, 0])
    bytes = file_fixture("tracks/run.fit").binread
    size = bytes.getbyte(0)
    body = bytes[size...-2]

    if with_zones
      fields = [0, 2, 4, 2, 28, 6, 6, 6, 2].pack("C*")
      body += [0x41, 0, 0].pack("C3") + [216].pack("v") + [3].pack("C") + fields
      body += [0x01, 18].pack("Cv") + seconds.map { it * 1000 }.pack("V7") + (FLOORS + [200]).pack("C6")
    end

    header = bytes[0, size].dup
    header[4, 4] = [body.bytesize].pack("V")
    header[12, 2] = [crc16(header[0, 12])].pack("v")
    header + body + [crc16(body)].pack("v")
  end

  def run_with(original, **attributes)
    activity = create(:activity, source: "garmin", distance_m: 1560.0, timer_s: 390.0, elapsed_s: 490.0, **attributes)
    zip = Zip::OutputStream.write_buffer { |out| out.put_next_entry("1_ACTIVITY.fit") && out.write(original) }.string
    activity.original.attach(io: StringIO.new(zip), filename: "#{activity.external_id}.zip", content_type: "application/zip")
    activity
  end

  def fitted(started_at, floors)
    create(:activity, started_at:, local_started_at: started_at, hr_zones: {"floors" => floors, "max_hr" => floors.last + 20, "seconds" => [1, 1, 1, 1, 1], "source" => "fit"})
  end

  test "processing stores the zones and seconds the FIT carries, and bands use them" do
    activity = run_with(fit(with_zones: true), started_at: Time.utc(2024, 3, 5, 6, 30))

    activity.process_original

    assert_equal({"floors" => FLOORS, "max_hr" => 200, "seconds" => [60, 180, 360, 0, 0], "source" => "fit"}, activity.reload.hr_zones)
    assert_equal 3, activity.bands["hr"].index(activity.bands["hr"].max) + 1
  end

  test "processing estimates from the earliest FIT sets when the file has no zones" do
    fitted(Time.utc(2018, 1, 1), [90, 110, 130, 150, 170])
    fitted(Time.utc(2018, 1, 2), FLOORS)
    fitted(Time.utc(2018, 1, 3), [110, 130, 150, 170, 190])
    activity = run_with(fit(with_zones: false), started_at: Time.utc(2024, 3, 5, 6, 30))

    activity.process_original
    zones = activity.reload.hr_zones

    assert_equal "estimated", zones["source"]
    assert_equal FLOORS, zones["floors"]
    assert_equal 200, zones["max_hr"]
    assert_predicate zones["seconds"].sum, :positive?
  end

  test "processing leaves the zones empty when there is no FIT set to estimate from" do
    activity = run_with(fit(with_zones: false), started_at: Time.utc(2024, 3, 5, 6, 30))

    activity.process_original

    assert_nil activity.reload.hr_zones
  end

  test "a FIT zone set with floors but no time keeps its floors and takes seconds from the track" do
    activity = run_with(fit(with_zones: true, seconds: [100] + [0] * 6), started_at: Time.utc(2024, 3, 5, 6, 30))

    activity.process_original
    zones = activity.reload.hr_zones

    assert_equal "fit", zones["source"]
    assert_equal FLOORS, zones["floors"]
    assert_predicate zones["seconds"].sum, :positive?
  end

  test "an estimated run whose heart rate never reaches zone 1 still stores the floors" do
    fitted(Time.utc(2018, 1, 1), [200, 210, 220, 230, 240])
    activity = run_with(fit(with_zones: false), started_at: Time.utc(2024, 3, 5, 6, 30))

    activity.process_original
    zones = activity.reload.hr_zones

    assert_equal "estimated", zones["source"]
    assert_equal [200, 210, 220, 230, 240], zones["floors"]
    assert_equal [0] * 5, zones["seconds"]
    assert_equal zones["floors"], HrZones.for(activity).floors
  end

  test "the estimate uses the 100 sets nearest before the run, or the earliest 100 when fewer come before it" do
    early = [90, 110, 130, 150, 170]
    late = [150, 160, 170, 180, 190]
    Activity::HrZoning::ESTIMATE_FROM.times { fitted(Time.utc(2018, 1, 1) + it.days, early) }
    (Activity::HrZoning::ESTIMATE_FROM + 1).times { fitted(Time.utc(2019, 6, 1) + it.days, late) }
    sets = Activity.fit_zone_sets

    assert_equal early, Activity.estimate_hr_zones(sets, Time.utc(2015, 1, 1))["floors"]
    assert_equal early, Activity.estimate_hr_zones(sets, Time.utc(2018, 3, 1))["floors"]
    assert_equal late, Activity.estimate_hr_zones(sets, Time.utc(2020, 6, 1))["floors"]
    assert_equal early, Activity.estimate_hr_zones(sets, Time.utc(2019, 1, 1))["floors"]
    assert_nil Activity.estimate_hr_zones([], Time.utc(2020, 1, 1))
  end

  test "a run after the first FIT zones is estimated from the sets before it and is not said to predate them" do
    fitted(Time.utc(2018, 1, 1), [90, 110, 130, 150, 170])
    fitted(Time.utc(2018, 2, 1), [100, 120, 140, 160, 180])
    activity = run_with(fit(with_zones: false), started_at: Time.utc(2024, 3, 5, 6, 30))

    activity.process_original

    assert_equal "estimated", activity.reload.hr_zones["source"]
    assert_not activity.predates_fit_zones?
    assert create(:activity, started_at: Time.utc(2015, 1, 1), local_started_at: Time.utc(2015, 1, 1)).predates_fit_zones?
  end

  test "backfill reads FIT zones, estimates tracked runs, skips runs without heart rate and is idempotent" do
    reference = run_with(fit(with_zones: true), started_at: Time.utc(2018, 5, 1))
    older = create(:activity, source: "strava", started_at: Time.utc(2015, 5, 1), local_started_at: Time.utc(2015, 5, 1))
    Track.create!(activity: older, data: {"t" => [0, 60, 120, 180], "d" => [0, 100, 200, 300], "hr" => [90, 130, 150, 170]})
    silent = create(:activity, source: "strava", started_at: Time.utc(2015, 5, 2), local_started_at: Time.utc(2015, 5, 2))
    Track.create!(activity: silent, data: {"t" => [0, 60], "d" => [0, 100]})

    2.times { assert_equal({"fit" => 1, "estimated" => 1, nil => 1}, Activity.backfill_hr_zones) }

    assert_equal "fit", reference.reload.hr_zones["source"]
    assert_equal "estimated", older.reload.hr_zones["source"]
    assert_equal [0, 60, 60, 60, 0], older.hr_zones["seconds"]
    assert_nil silent.reload.hr_zones
  end

  test "backfill drops stored FIT zones the original no longer yields" do
    run = run_with(fit(with_zones: false), started_at: Time.utc(2018, 5, 1), hr_zones: {"floors" => FLOORS, "max_hr" => 200, "seconds" => [0] * 5, "source" => "fit"})

    Activity.backfill_hr_zones

    assert_nil run.reload.hr_zones
  end
end
