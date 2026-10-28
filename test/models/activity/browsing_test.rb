require "test_helper"

class Activity::BrowsingTest < ActiveSupport::TestCase
  def run_at(time, **attrs)
    create(:activity, local_started_at: time, started_at: time, **attrs)
  end

  test "previous and next follow local start time" do
    first = run_at(Time.utc(2024, 3, 1, 7))
    second = run_at(Time.utc(2024, 3, 2, 7))
    third = run_at(Time.utc(2024, 3, 3, 7))

    assert_equal first, second.previous_run
    assert_equal third, second.next_run
    assert_nil first.previous_run
    assert_nil third.next_run
  end

  test "previous and next break ties by id" do
    first = run_at(Time.utc(2024, 3, 1, 7))
    second = run_at(Time.utc(2024, 3, 1, 7))

    assert_equal first, second.previous_run
    assert_equal second, first.next_run
  end

  test "same day runs are ordered and exclude other days" do
    evening = run_at(Time.utc(2024, 3, 1, 19))
    morning = run_at(Time.utc(2024, 3, 1, 7))
    run_at(Time.utc(2024, 3, 2, 7))
    run_at(Time.utc(2024, 2, 29, 23, 59))

    assert_equal [morning, evening], evening.same_day_runs.to_a
  end

  test "longest rank counts longer runs" do
    run_at(Time.utc(2024, 3, 1), distance_m: 20_000, timer_s: 6000)
    middle = run_at(Time.utc(2024, 3, 2), distance_m: 10_000)
    run_at(Time.utc(2024, 3, 3), distance_m: 5000, timer_s: 1500)

    assert_equal 2, middle.longest_rank
    assert_equal 3, middle.run_count
  end

  test "similar rank only considers runs within ten percent by pace" do
    run = run_at(Time.utc(2024, 3, 1), distance_m: 10_000, timer_s: 3000)
    run_at(Time.utc(2024, 3, 2), distance_m: 10_900, timer_s: 3000)
    run_at(Time.utc(2024, 3, 3), distance_m: 9100, timer_s: 3000)
    run_at(Time.utc(2024, 3, 4), distance_m: 11_500, timer_s: 2000)
    run_at(Time.utc(2024, 3, 5), distance_m: 10_000, timer_s: 4000)

    assert_equal 4, run.similar_count
    assert_equal 2, run.similar_rank
  end

  test "fastest similar is windowed up to and including the run, top five by pace" do
    run = run_at(Time.utc(2024, 6, 1), distance_m: 10_000, timer_s: 3000)
    old = run_at(Time.utc(2023, 6, 1), distance_m: 10_000, timer_s: 2000)
    recent = run_at(Time.utc(2024, 5, 1), distance_m: 10_000, timer_s: 2500)
    run_at(Time.utc(2024, 7, 1), distance_m: 10_000, timer_s: 2000)
    run_at(Time.utc(2024, 5, 2), distance_m: 3000, timer_s: 600)
    5.times { |index| run_at(Time.utc(2024, 5, 10 + index), distance_m: 10_000, timer_s: 3500 + index) }

    assert_equal [recent, run], run.fastest_similar(90).first(2)
    assert_equal 5, run.fastest_similar(90).size
    assert_not_includes run.fastest_similar(365).to_a, old
    assert_includes run.fastest_similar(365).to_a, run
    assert_includes run.fastest_similar.to_a, old
    assert_equal 5, run.fastest_similar.size
  end

  test "rank distributions include ties and the same all-time cohorts as ranks" do
    run = run_at(Time.utc(2024, 3, 1), distance_m: 10_000, timer_s: 3000)
    run_at(Time.utc(2024, 3, 2), distance_m: 10_000, timer_s: 3000)
    run_at(Time.utc(2024, 3, 3), distance_m: 9000, timer_s: 2250)
    run_at(Time.utc(2024, 3, 4), distance_m: 11_000, timer_s: 3850)
    run_at(Time.utc(2024, 3, 5), distance_m: 11_001, timer_s: 2200)

    assert_equal [9.0, 10.0, 10.0, 11.0, 11.001], run.distance_distribution.sort
    assert_equal [250.0, 300.0, 300.0, 350.0], run.similar_pace_distribution.sort
    assert_equal run.run_count, run.distance_distribution.size
    assert_equal run.similar_count, run.similar_pace_distribution.size
    assert_equal 3, run.longest_rank
    assert_equal 2, run.similar_rank
  end

  test "a sole run is included in both distributions" do
    run = run_at(Time.utc(2024, 3, 1), distance_m: 5000, timer_s: 1500)

    assert_equal [5.0], run.distance_distribution
    assert_equal [300.0], run.similar_pace_distribution
    assert_equal 1, run.longest_rank
    assert_equal 1, run.similar_rank
  end

  test "calendar years list every year newest first with the latest run" do
    run_at(Time.utc(2022, 1, 5, 7))
    old = run_at(Time.utc(2022, 9, 5, 7))
    run = run_at(Time.utc(2024, 3, 1, 7))
    latest = run_at(Time.utc(2024, 11, 2, 7))

    assert_equal [2024, 2022], run.calendar_years.keys
    assert_equal [latest.id, old.id], run.calendar_years.values
  end

  test "calendar months cover only the run's year and open the latest run of each month" do
    run_at(Time.utc(2023, 2, 1, 7))
    early = run_at(Time.utc(2024, 3, 1, 7))
    late = run_at(Time.utc(2024, 3, 20, 7))
    other = run_at(Time.utc(2024, 7, 4, 7))

    assert_equal({3 => late.id, 7 => other.id}, early.calendar_months)
  end

  test "calendar days list the whole month with first run, race flag and total km" do
    first = run_at(Time.utc(2024, 2, 10, 6), distance_m: 5000, timer_s: 1500)
    run_at(Time.utc(2024, 2, 10, 18), distance_m: 7000, timer_s: 2100, race: true)
    run_at(Time.utc(2024, 3, 1, 7))

    days = first.calendar_days

    assert_equal 29, days.size
    assert_equal Date.new(2024, 2, 1), days.first[:date]
    assert_nil days.first[:id]
    assert_not days.first[:race]
    assert_equal 0.0, days.first[:km]
    assert_equal first.id, days[9][:id]
    assert days[9][:race]
    assert_in_delta 12.0, days[9][:km], 1e-9
  end

  test "earlier runs carry weather and exclude later ones" do
    run = run_at(Time.utc(2024, 3, 2))
    earlier = run_at(Time.utc(2024, 3, 1), weather: {"temperature" => 12.5})
    run_at(Time.utc(2024, 3, 3))

    assert_equal [earlier], run.earlier_runs.to_a
    assert_equal 12.5, run.earlier_runs.first.weather["temperature"]
  end

  test "finish times use the run's vdot" do
    run = run_at(Time.utc(2024, 3, 1))

    assert_equal %w[5K 10K Half Marathon], run.finish_times.map(&:first)
    assert_in_delta Vdot.time_for(5000, run.vdot), run.finish_times.first.last, 1e-9
  end

  test "listed filters by period and whitelists the sort" do
    short = run_at(Time.utc(2023, 5, 1), distance_m: 5000, timer_s: 1500)
    long = run_at(Time.utc(2024, 3, 1), distance_m: 20_000, timer_s: 6000)
    other = run_at(Time.utc(2024, 4, 1), distance_m: 10_000)

    assert_equal [short], Activity.listed(year: 2023).to_a
    assert_equal [long], Activity.listed(year: 2024, month: 3).to_a
    assert_equal [short, other, long], Activity.listed(sort: "km", dir: "asc").to_a
    assert_equal [other, long, short], Activity.listed(sort: "date; DROP TABLE activities", dir: "sideways").to_a
  end

  test "null values sort last in both directions" do
    with = run_at(Time.utc(2024, 3, 1), elevation_gain_m: 150)
    without = run_at(Time.utc(2024, 3, 2))

    assert_equal [with, without], Activity.listed(sort: "elevation", dir: "asc").to_a
    assert_equal [with, without], Activity.listed(sort: "elevation", dir: "desc").to_a
  end

  test "prior training covers 90 days before the run and excludes it" do
    run = run_at(Time.utc(2024, 6, 10, 18))
    inside = run_at(Time.utc(2024, 3, 12, 6), distance_m: 5000, timer_s: 1500, avg_hr: 150)
    earlier_today = run_at(Time.utc(2024, 6, 10, 7))
    run_at(Time.utc(2024, 3, 11, 23, 59))
    run_at(Time.utc(2024, 6, 10, 19))

    prior = run.prior_training

    assert_equal [inside, earlier_today].map { it.local_started_at.to_i * 1000 }, prior.pluck(:t)
    assert_equal({t: Time.utc(2024, 3, 12, 6).to_i * 1000, km: 5.0, pace: 300.0, hr: 150, vdot: inside.vdot.round(2), s: 1500, url: "/runs/#{inside.id}"}, prior.first)
  end

  test "a training point holds the run's own figures" do
    run = run_at(Time.utc(2024, 6, 10, 18), distance_m: 5000, timer_s: 1500, avg_hr: nil, race: true)

    assert_equal({km: 5.0, pace: 300.0, hr: nil, vdot: run.vdot.round(2), s: 1500}, run.training_point)
  end

  test "prior training is empty for the first run" do
    assert_empty run_at(Time.utc(2024, 3, 1)).prior_training
  end

  test "years and months with runs" do
    run_at(Time.utc(2023, 5, 1))
    run_at(Time.utc(2024, 3, 1))
    run_at(Time.utc(2024, 3, 9))

    assert_equal [2024, 2023], Activity.years_with_runs
    assert_equal [3], Activity.months_with_runs(2024)
  end
end
