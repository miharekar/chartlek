require "test_helper"

class NotablesTest < ActiveSupport::TestCase
  setup { @activity = build_run(Time.utc(2024, 3, 5, 7, 30)) }

  test "longest run reports the largest window that holds" do
    previous = [build_run(Time.utc(2024, 2, 1, 7, 30), distance_m: 5000), build_run(Time.utc(2023, 7, 1, 7, 30), distance_m: 15_000)]

    assert_includes notables(@activity, previous), "Longest run in 6 months"
  end

  test "longest run says ever when nothing earlier is longer" do
    assert_includes notables(@activity, [build_run(Time.utc(2020, 2, 1, 7, 30), distance_m: 5000)]), "Longest run ever"
  end

  test "nothing is longest or fastest without earlier runs" do
    assert_empty notables(@activity, []).grep(/Longest|Fastest/)
  end

  test "later runs are ignored" do
    assert_empty notables(@activity, [build_run(Time.utc(2024, 4, 1, 7, 30), distance_m: 50_000)]).grep(/Longest/)
  end

  test "fastest run for a similar distance compares only runs within 10%" do
    previous = [
      build_run(Time.utc(2024, 2, 1, 7, 30), distance_m: 10_500, timer_s: 3600),
      build_run(Time.utc(2023, 1, 1, 7, 30), distance_m: 9500, timer_s: 2700),
      build_run(Time.utc(2022, 1, 1, 7, 30), distance_m: 20_000, timer_s: 4000)
    ]

    assert_includes notables(@activity, previous), "Fastest run for a similar distance in 12 months"
    assert_includes notables(@activity, previous + [build_run(Time.utc(2023, 9, 1, 7, 30), distance_m: 10_200, timer_s: 2400)]), "Fastest run for a similar distance in 6 months"
  end

  test "most elevation gain" do
    @activity.elevation_gain_m = 200
    previous = [build_run(Time.utc(2024, 2, 1, 7, 30), elevation_gain_m: 100), build_run(Time.utc(2023, 7, 1, 7, 30), elevation_gain_m: nil)]

    assert_includes notables(@activity, previous), "Most elevation gain ever"
  end

  test "hottest and coldest run use weather and skip runs without it" do
    @activity.weather = {"temperature" => 30.0}
    previous = [build_run(Time.utc(2024, 2, 1, 7, 30), weather: {"temperature" => 20.0}), build_run(Time.utc(2023, 7, 1, 7, 30))]

    assert_includes notables(@activity, previous), "Hottest run ever"

    @activity.weather = {"temperature" => -5.0}

    assert_includes notables(@activity, previous), "Coldest run ever"
  end

  test "weather notables are skipped without weather" do
    assert_empty notables(@activity, [build_run(Time.utc(2024, 2, 1, 7, 30), weather: {"temperature" => 20.0})]).grep(/Hottest|Coldest|sunrise|sunset/)
  end

  test "run during sunrise or sunset checks start and end" do
    @activity.weather = {"temperature" => 5.0, "sunrise" => "2024-03-05T07:10", "sunset" => "2024-03-05T17:40"}

    assert_includes notables(@activity, []), "Run during sunrise"
    assert_not_includes notables(@activity, []), "Run during sunset"

    @activity.local_started_at = Time.utc(2024, 3, 5, 16, 55)
    @activity.elapsed_s = 3000

    assert_includes notables(@activity, []), "Run during sunset"
  end

  test "full moon and new moon" do
    assert_includes notables(build_run(Time.utc(2024, 4, 23, 20, 0)), []), "Run on a full moon"
    assert_includes notables(build_run(Time.utc(2024, 4, 8, 20, 0)), []), "Run on a new moon"
    assert_empty notables(@activity, []).grep(/moon/)
  end

  test "first run at a new location" do
    @activity.location_name = "Ljubljana"

    assert_includes notables(@activity, [build_run(Time.utc(2024, 2, 1, 7, 30), location_name: "Bled")]), "First run at Ljubljana"
    assert_empty notables(@activity, [build_run(Time.utc(2024, 2, 1, 7, 30), location_name: "Ljubljana")]).grep(/First run at/)
  end

  test "earliest and latest start" do
    previous = [build_run(Time.utc(2024, 2, 1, 8, 0)), build_run(Time.utc(2023, 10, 1, 6, 0))]

    assert_includes notables(@activity, previous), "Earliest start in 3 months"

    late = build_run(Time.utc(2024, 3, 5, 21, 0))

    assert_includes notables(late, previous), "Latest start ever"
  end

  test "extends the longest streak" do
    previous = (1..4).map { build_run(Time.utc(2024, 3, it, 7, 30)) } + (1..3).map { build_run(Time.utc(2024, 1, it, 7, 30)) }

    assert_includes notables(@activity, previous), "Extends your longest streak to 5 days"
    assert_empty notables(@activity, previous + (10..20).map { build_run(Time.utc(2023, 12, it, 7, 30)) }).grep(/streak/)
  end

  test "first run of the year" do
    assert_includes notables(@activity, [build_run(Time.utc(2023, 12, 30, 7, 30))]), "First run of the year"
    assert_empty notables(@activity, [build_run(Time.utc(2024, 1, 30, 7, 30))]).grep(/First run of the year/)
  end

  test "lifetime distance milestone" do
    previous = [build_run(Time.utc(2024, 2, 1, 7, 30), distance_m: 995_000)]

    assert_includes notables(@activity, previous), "Passed 1,000 km lifetime"
    assert_empty notables(@activity, [build_run(Time.utc(2024, 2, 1, 7, 30), distance_m: 900_000)]).grep(/lifetime/)
  end

  test "moon phase matches known full and new moons" do
    assert_equal :full, Notables::Moon.phase(Time.utc(2024, 4, 23, 23, 49))
    assert_equal :new, Notables::Moon.phase(Time.utc(2024, 4, 8, 18, 21))
    assert_nil Notables::Moon.phase(Time.utc(2024, 4, 15, 12, 0))
  end

  private
  def build_run(local_started_at, **attributes)
    build(:activity, local_started_at:, **attributes)
  end

  def notables(activity, previous)
    Notables.for(activity, previous + [activity])
  end
end
