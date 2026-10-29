require "test_helper"

class PrProgressTest < ActiveSupport::TestCase
  setup { @today = Date.new(2024, 6, 30) }

  test "is empty without runs" do
    assert PrProgress.new([], today: @today).empty?
  end

  test "the window defaults to the last twelve months through today and follows from and to" do
    create(:activity, local_started_at: Time.utc(2024, 5, 1, 8))
    ms = ->(date) { date.to_time(:utc).to_i * 1000 }

    assert_equal [ms.(Date.new(2023, 6, 30)), ms.(Date.new(2024, 7, 1))], PrProgress.new(Activity.all, today: @today).data[:window]
    assert_equal [ms.(Date.new(2024, 2, 1)), ms.(Date.new(2024, 4, 1))], PrProgress.new(Activity.all, today: @today, from: "2024-02-01", to: "2024-03-31").data[:window]
    assert_equal [ms.(Date.new(2023, 6, 30)), ms.(Date.new(2024, 7, 1))], PrProgress.new(Activity.all, today: @today, from: "nope", to: "2024-02-31").data[:window]
  end

  test "serializes one row per run in time order with its bucket" do
    late = create(:activity, distance_m: 10_400, timer_s: 3120, local_started_at: Time.utc(2024, 6, 1, 8), name: "Late", race: true)
    early = create(:activity, distance_m: 12_000, timer_s: 3600, local_started_at: Time.utc(2024, 5, 1, 8), name: "Early")

    data = PrProgress.new(Activity.all, today: @today).data
    columns = data[:columns]
    rows = data[:runs].map { columns.zip(it).to_h }

    assert_equal [early.id, late.id], rows.pluck("id")
    assert_nil rows[0]["bucket"]
    assert_nil rows[0]["best"]
    assert_equal 2, rows[1]["bucket"]
    assert_in_delta 3000, rows[1]["best"], 0.01
    assert_equal Time.utc(2024, 6, 1, 8).to_i * 1000, rows[1]["time"]
    assert_equal 10.4, rows[1]["distance"]
    assert_equal 300, rows[1]["pace"]
    assert_equal 1, rows[1]["race"]
    assert_equal "/runs/#{late.id}", rows[1]["url"]
    assert_equal "Late", rows[1]["name"]
    assert_equal late.vdot.round(2), rows[1]["vdot"]
  end

  test "frontier holds the all-time PR per benchmark" do
    create(:activity, distance_m: 10_000, timer_s: 3000, local_started_at: Time.utc(2023, 1, 1, 8))
    pr = create(:activity, distance_m: 10_000, timer_s: 2700, local_started_at: Time.utc(2024, 1, 1, 8), race: true)
    create(:activity, distance_m: 5000, timer_s: 1500, local_started_at: Time.utc(2024, 2, 1, 8))

    frontier = PrProgress.new(Activity.all, today: @today).data[:frontier]

    assert_equal [1, 2], frontier.pluck(:bucket)
    assert_equal 2700, frontier.last[:time]
    assert_equal 270, frontier.last[:pace]
    assert frontier.last[:race]
    assert_equal pr.id, frontier.last[:id]
    assert_equal "/runs/#{pr.id}", frontier.last[:url]
    assert_equal Time.utc(2024, 1, 1, 8).to_i * 1000, frontier.last[:date]
  end

  test "ships a prediction table per benchmark" do
    create(:activity)

    benchmarks = PrProgress.new(Activity.all, today: @today).data[:benchmarks]

    assert_equal PersonalRecords::BENCHMARKS.map(&:first), benchmarks.pluck(:name)
    assert_equal Vdot.time_table(10_000), benchmarks[2][:table]
  end

  test "reference is the highest VDOT run in the period" do
    create(:activity, local_started_at: Time.utc(2024, 6, 20, 8), distance_m: 10_000, timer_s: 3300)
    best = create(:activity, local_started_at: Time.utc(2024, 6, 10, 8), distance_m: 10_000, timer_s: 2700)
    create(:activity, local_started_at: Time.utc(2024, 6, 25, 8), distance_m: 10_000, timer_s: 3000)

    assert_equal best, PrProgress.new(Activity.all, today: @today).reference_for(30)
  end

  test "reference period is the last N days ending today, inclusive" do
    outside = create(:activity, local_started_at: Time.utc(2024, 5, 31, 23), distance_m: 10_000, timer_s: 2400)
    inside = create(:activity, local_started_at: Time.utc(2024, 6, 1, 0), distance_m: 10_000, timer_s: 3000)
    progress = PrProgress.new(Activity.all, today: @today)

    assert_equal inside, progress.reference_for(30)
    assert_equal outside, progress.reference_for(60)
  end

  test "reference ties go to the most recent run" do
    create(:activity, local_started_at: Time.utc(2024, 6, 10, 8), distance_m: 10_000, timer_s: 3000)
    recent = create(:activity, local_started_at: Time.utc(2024, 6, 20, 8), distance_m: 10_000, timer_s: 3000)
    create(:activity, local_started_at: Time.utc(2024, 6, 15, 8), distance_m: 10_000, timer_s: 3000)

    assert_equal recent, PrProgress.new(Activity.all, today: @today).reference_for(30)
  end

  test "reference ignores runs without a VDOT and is nil when the period is empty" do
    create(:activity, local_started_at: Time.utc(2024, 6, 20, 8), distance_m: 300, timer_s: 100)
    create(:activity, local_started_at: Time.utc(2024, 1, 20, 8))
    progress = PrProgress.new(Activity.all, today: @today)

    assert_nil progress.reference_for(30)
    assert_nil progress.data[:references][30]
    assert_nil progress.reference_for(90)
  end

  test "references are keyed by period" do
    old = create(:activity, local_started_at: Time.utc(2024, 4, 20, 8), distance_m: 10_000, timer_s: 2400)
    recent = create(:activity, local_started_at: Time.utc(2024, 6, 20, 8), distance_m: 10_000, timer_s: 3000)

    references = PrProgress.new(Activity.all, today: @today).data[:references]

    assert_equal({30 => recent.id, 60 => recent.id, 90 => old.id}, references)
  end

  test "magic targets ship bucket, target and percent" do
    create(:activity, distance_m: 42_195, timer_s: 12_032)

    magic = PrProgress.new(Activity.all, today: @today).data[:magic]

    assert_equal [{bucket: 7, target: 11_700, percent: 2.76}], magic
  end
end
