require "test_helper"

class GoalTest < ActiveSupport::TestCase
  test "starts_on snaps to the start of the month or year" do
    month = Goal.create!(period: "month", starts_on: Date.new(2026, 10, 17), distance_km: 150)
    year = Goal.create!(period: "year", starts_on: Date.new(2026, 10, 17), distance_km: 1800)

    assert_equal Date.new(2026, 10, 1), month.starts_on
    assert_equal Date.new(2026, 10, 31), month.ends_on
    assert_equal 31, month.days
    assert_equal Date.new(2026, 1, 1), year.starts_on
    assert_equal 365, year.days
    assert_equal ["October 2026", "2026"], [month.title, year.title]
  end

  test "distance is entered in km and stored in metres" do
    goal = Goal.new(distance_km: "12.5")

    assert_equal 12_500.0, goal.distance_m
    assert_equal 12.5, goal.distance_km
  end

  test "rejects a missing, non-numeric or non-positive distance" do
    ["", "abc", "0", "-3", "1e999", "inf", "200000"].each do |km|
      goal = Goal.new(period: "month", starts_on: Date.new(2026, 10, 1), distance_km: km)

      assert_not goal.valid?, km.inspect
      assert goal.errors[:distance_m].any?, km.inspect
    end
  end

  test "rejects an unknown period and a missing date" do
    assert_not Goal.new(period: "week", starts_on: Date.new(2026, 10, 1), distance_km: 10).valid?
    assert_not Goal.new(period: "month", distance_km: 10).valid?
  end

  test "one goal per period and start, however the date was typed" do
    Goal.create!(period: "month", starts_on: Date.new(2026, 10, 1), distance_km: 100)

    assert_not Goal.new(period: "month", starts_on: Date.new(2026, 10, 20), distance_km: 50).valid?
    assert Goal.new(period: "year", starts_on: Date.new(2026, 10, 20), distance_km: 50).valid?
    assert Goal.new(period: "month", starts_on: Date.new(2026, 11, 1), distance_km: 50).valid?
  end

  test "the database enforces the same uniqueness" do
    Goal.create!(period: "month", starts_on: Date.new(2026, 10, 1), distance_km: 100)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Goal.new(period: "month", starts_on: Date.new(2026, 10, 1), distance_km: 50).save!(validate: false)
    end
  end

  test "progress reads the goal's runs by local date" do
    goal = Goal.create!(period: "month", starts_on: Date.new(2026, 10, 1), distance_km: 100)
    create(:activity, started_at: Time.utc(2026, 9, 30, 23, 30), local_started_at: Time.utc(2026, 10, 1, 1, 30), distance_m: 10_000)
    create(:activity, started_at: Time.utc(2026, 9, 25, 7), local_started_at: Time.utc(2026, 9, 25, 7), distance_m: 7_000)

    assert_equal [10.0], goal.progress(today: Date.new(2026, 10, 1)).cumulative
  end
end
