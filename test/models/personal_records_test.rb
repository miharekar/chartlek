require "test_helper"

class PersonalRecordsTest < ActiveSupport::TestCase
  test "benchmarks are in order" do
    assert_equal ["3 km", "5 km", "10 km", "15 km", "20 km", "Half marathon", "40 km", "Marathon", "50 km", "100 km"], PersonalRecords::BENCHMARKS.map(&:first)
  end

  test "bucket_for covers each benchmark from its distance up to but excluding 1 km beyond it" do
    PersonalRecords::BENCHMARKS.each do |name, distance_m|
      assert_nil PersonalRecords.bucket_for(build(:activity, distance_m: distance_m - 0.1, timer_s: 1000)), "#{name} below"
      assert_equal name, PersonalRecords.bucket_for(build(:activity, distance_m:, timer_s: 1000)).name, "#{name} lower edge"
      assert_equal name, PersonalRecords.bucket_for(build(:activity, distance_m: distance_m + 999.9, timer_s: 1000)).name, "#{name} upper edge"
      assert_nil PersonalRecords.bucket_for(build(:activity, distance_m: distance_m + 1000, timer_s: 1000)), "#{name} beyond"
    end
  end

  test "bucket_for returns the benchmark and the time interpolated at constant pace" do
    bucket = PersonalRecords.bucket_for(build(:activity, distance_m: 10_400, timer_s: 3120))

    assert_equal "10 km", bucket.name
    assert_equal 10_000, bucket.distance_m
    assert_in_delta 3000, bucket.time_s, 1e-9
  end

  test "bucket_for is nil between buckets" do
    assert_nil PersonalRecords.bucket_for(build(:activity, distance_m: 12_000, timer_s: 3600))
  end

  test "is empty without qualifying runs" do
    assert_empty PersonalRecords.for([])
    assert_empty PersonalRecords.for([build(:activity, distance_m: 900, timer_s: 400)])
  end

  test "run qualifies from the benchmark up to but excluding 1 km beyond it" do
    below = build(:activity, distance_m: 4999.9, timer_s: 1500)
    lower_edge = build(:activity, distance_m: 5000, timer_s: 1600)
    upper_edge = build(:activity, distance_m: 5999.9, timer_s: 2000)
    beyond = build(:activity, distance_m: 6000, timer_s: 1000)

    record = PersonalRecords.for([below, lower_edge, upper_edge, beyond]).find { it.name == "5 km" }

    assert_equal 2, record.count
    assert_same lower_edge, record.activity
  end

  test "picks the lowest time interpolated at constant pace" do
    short_slow = build(:activity, distance_m: 5000, timer_s: 1500)
    long_fast = build(:activity, distance_m: 5800, timer_s: 1650)

    record = PersonalRecords.for([short_slow, long_fast]).find { it.name == "5 km" }

    assert_same long_fast, record.activity
    assert_in_delta 1650 * 5000 / 5800.0, record.time_s, 1e-9
  end

  test "derives distance, pace, speed and race flag" do
    race = build(:activity, distance_m: 10_000, timer_s: 3000, race: true)

    record = PersonalRecords.for([race]).find { it.name == "10 km" }

    assert_equal 10_000, record.distance_m
    assert_in_delta 300, record.pace, 1e-9
    assert_in_delta 12, record.speed_kmh, 1e-9
    assert record.race
    assert_equal 1, record.count
  end

  test "race flag follows the PR run" do
    race = build(:activity, distance_m: 10_000, timer_s: 3200, race: true)
    training = build(:activity, distance_m: 10_000, timer_s: 3100)

    record = PersonalRecords.for([race, training]).find { it.name == "10 km" }

    assert_same training, record.activity
    assert_not record.race
  end

  test "a run only qualifies for the benchmark it is within 1 km of" do
    run = build(:activity, distance_m: 10_500, timer_s: 3150)

    names = PersonalRecords.for([run]).map(&:name)

    assert_equal ["10 km"], names
  end

  test "returns entries in benchmark order" do
    marathon = build(:activity, distance_m: 42_300, timer_s: 12_000)
    five_k = build(:activity, distance_m: 5100, timer_s: 1500)
    three_k = build(:activity, distance_m: 3100, timer_s: 800)

    assert_equal ["3 km", "5 km", "Marathon"], PersonalRecords.for([marathon, five_k, three_k]).map(&:name)
  end

  test "works on a relation" do
    create(:activity, distance_m: 10_000, timer_s: 3000)
    create(:activity, distance_m: 10_200, timer_s: 2900)

    record = PersonalRecords.for(Activity.where(distance_m: 10_000..)).find { it.name == "10 km" }

    assert_equal 2, record.count
    assert_in_delta 2900 * 10_000 / 10_200.0, record.time_s, 1e-9
  end
end
