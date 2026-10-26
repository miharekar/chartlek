require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "factory is valid" do
    assert build(:activity).valid?
  end

  test "requires core attributes" do
    activity = Activity.new

    assert_not activity.valid?
    %i[external_id started_at local_started_at activity_type distance_m timer_s].each do |attribute|
      assert_includes activity.errors.attribute_names, attribute
    end
  end

  test "source must be garmin, strava or smashrun" do
    assert build(:activity, source: "strava").valid?
    assert build(:activity, source: "smashrun").valid?
    assert_not build(:activity, source: "polar").valid?
  end

  test "garmin_url and strava_url link to the source" do
    assert_equal "https://connect.garmin.com/app/activity/42", build(:activity, source: "garmin", external_id: "42").garmin_url
    assert_nil build(:activity, source: "strava", external_id: "42").garmin_url
    assert_equal "https://www.strava.com/activities/99", build(:activity, source: "garmin", strava_id: 99).strava_url
    assert_nil build(:activity, source: "garmin").strava_url
  end

  test "external_id is unique per source" do
    create(:activity, external_id: "42")

    assert_not build(:activity, external_id: "42").valid?
    assert build(:activity, source: "strava", external_id: "42").valid?
  end

  test "today is the UTC date without runs" do
    assert_equal Date.current, Activity.today
  end

  test "today applies the offset of the newest run" do
    travel_to Time.utc(2026, 10, 25, 23, 30) do
      create(:activity, started_at: Time.utc(2026, 10, 20, 6), local_started_at: Time.utc(2026, 10, 20, 8))

      assert_equal Date.new(2026, 10, 26), Activity.today
    end
  end

  test "today is the local date at 00:30 local before any run that day" do
    travel_to Time.utc(2026, 10, 24, 22, 30) do
      create(:activity, started_at: Time.utc(2026, 10, 24, 5), local_started_at: Time.utc(2026, 10, 24, 7))

      assert_equal Date.new(2026, 10, 25), Activity.today
    end
  end

  test "today does not run ahead for a western offset" do
    travel_to Time.utc(2026, 10, 25, 3) do
      create(:activity, started_at: Time.utc(2026, 10, 24, 14), local_started_at: Time.utc(2026, 10, 24, 8))

      assert_equal Date.new(2026, 10, 24), Activity.today
    end
  end
end
