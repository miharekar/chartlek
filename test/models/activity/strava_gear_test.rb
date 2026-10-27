require "test_helper"

class Activity::StravaGearTest < ActiveSupport::TestCase
  ACTIVITIES_URL = "https://www.strava.com/api/v3/athlete/activities"
  ATHLETE_URL = "https://www.strava.com/api/v3/athlete"
  GEAR_URL = "https://www.strava.com/api/v3/gear/g1"

  setup do
    @profile = Profile.instance
    @profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 6.hours.from_now.to_i)
    @profile.update!(strava_scope: "read,activity:read_all,profile:read_all")
    @run = create(:activity, strava_id: 555)
  end

  def summaries(*rows)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1")).to_return(body: rows.to_json)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "2")).to_return(body: "[]")
  end

  def gear(id = "g1", **extra)
    stub_request(:get, "https://www.strava.com/api/v3/gear/#{id}").to_return(body: {id:, name: "Synthetic Shoe", brand_name: "Acme", model_name: "Zoom"}.merge(extra).to_json)
  end

  test "a full pass reads gear ids, fetches each gear once and stamps the profile" do
    other = create(:activity, strava_id: 556)
    summaries({"id" => 555, "gear_id" => "g1"}, {"id" => 556, "gear_id" => "g1"})
    stub_request(:get, ATHLETE_URL).to_return(body: {shoes: [{id: "g2"}]}.to_json)
    gear
    gear("g2")

    Activity.sync_strava_gear_now(full: true)

    assert_equal "g1", @run.reload.strava_gear_id
    assert_equal "g1", other.reload.strava_gear_id
    assert_requested :get, GEAR_URL, times: 1
    assert_equal %w[g1 g2], Gear.order(:strava_id).pluck(:strava_id)
    assert_equal "Acme", Gear.find_by(strava_id: "g1").brand_name
    assert_equal "Synthetic Shoe", Gear.find_by(strava_id: "g1").summary["name"]
    assert_not_nil @profile.reload.strava_gear_synced_at
  end

  test "an activity can carry a gear id before its gear row exists" do
    Activity.read_strava_gear_ids([{"id" => 555, "gear_id" => "g9"}])

    assert_equal "g9", @run.reload.strava_gear_id
    assert_equal 0, Gear.count
  end

  test "null gear clears the id, a missing key leaves it" do
    @run.update!(strava_gear_id: "g1")

    Activity.read_strava_gear_ids([{"id" => 555}])
    assert_equal "g1", @run.reload.strava_gear_id

    Activity.read_strava_gear_ids([{"id" => 555, "gear_id" => nil}])
    assert_nil @run.reload.strava_gear_id
  end

  test "retired is false when the payload has no flag and follows it when present" do
    gear
    gear("g2", retired: true)

    Gear.sync(%w[g1 g2], client: Strava::Client.new)

    assert_not Gear.find_by(strava_id: "g1").retired
    assert Gear.find_by(strava_id: "g2").retired
  end

  test "gear is refreshed only when stale unless forced" do
    gear
    Gear.sync(%w[g1], client: Strava::Client.new)
    Gear.sync(%w[g1], client: Strava::Client.new)
    assert_requested :get, GEAR_URL, times: 1

    Gear.find_by(strava_id: "g1").update!(synced_at: 8.days.ago)
    Gear.sync(%w[g1], client: Strava::Client.new)
    assert_requested :get, GEAR_URL, times: 2

    Gear.sync(%w[g1], client: Strava::Client.new, force: true)
    assert_requested :get, GEAR_URL, times: 3
  end

  test "a 404 stores the gear as synced with no summary, retried weekly" do
    stub_request(:get, GEAR_URL).to_return(status: 404, body: "{}")

    Gear.sync(%w[g1], client: Strava::Client.new)

    gear = Gear.find_by!(strava_id: "g1")
    assert_nil gear.summary
    assert_nil gear.name
    assert_not gear.stale?
  end

  test "a 429 or 500 raises, stores nothing and stamps nothing" do
    summaries({"id" => 555, "gear_id" => "g1"})
    stub_request(:get, ATHLETE_URL).to_return(body: "{}")

    [429, 500].each do |status|
      stub_request(:get, GEAR_URL).to_return(status:, body: "{}")

      assert_raises(Strava::Client::Error) { Activity.sync_strava_gear_now(full: true) }

      assert_equal 0, Gear.count
      assert_nil @profile.reload.strava_gear_synced_at
    end
  end

  test "a failed refresh keeps what the gear already had" do
    gear
    Gear.sync(%w[g1], client: Strava::Client.new)
    stub_request(:get, GEAR_URL).to_return(status: 404, body: "{}")

    Gear.sync(%w[g1], client: Strava::Client.new, force: true)

    assert_equal "Synthetic Shoe", Gear.find_by(strava_id: "g1").name
  end

  test "a dead gear id does not stop a full pass" do
    @run.update!(strava_gear_id: "g0")
    create(:activity, strava_id: 556, strava_gear_id: "g1")
    summaries({"id" => 555, "gear_id" => "g0"}, {"id" => 556, "gear_id" => "g1"})
    stub_request(:get, ATHLETE_URL).to_return(body: "{}")
    stub_request(:get, "https://www.strava.com/api/v3/gear/g0").to_return(status: 404, body: "{}")
    gear

    Activity.sync_strava_gear_now(full: true)

    assert_equal %w[g0 g1], Gear.order(:strava_id).pluck(:strava_id)
    assert_not_nil @profile.reload.strava_gear_synced_at
  end

  test "a 401 on a gear still disconnects" do
    stub_request(:get, GEAR_URL).to_return(status: 401, body: "{}")

    assert_raises(Strava::Client::NotConnected) { Gear.sync(%w[g1], client: Strava::Client.new) }
    assert_not @profile.reload.strava_connected?
  end

  test "a row another pass already created is updated, not duplicated" do
    Gear.create!(strava_id: "g1")
    gear

    Gear.sync(%w[g1], client: Strava::Client.new)

    assert_equal 1, Gear.count
    assert_equal "Synthetic Shoe", Gear.find_by(strava_id: "g1").name
  end

  test "the recent pass asks once for the last 30 days and applies a fixed gear" do
    @run.update!(strava_gear_id: "g1")
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "1", "after" => /\d+/)).to_return(body: [{"id" => 555, "gear_id" => "g2"}].to_json)
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("page" => "2")).to_return(body: "[]")
    gear("g2")

    Activity.sync_strava_gear_now

    assert_equal "g2", @run.reload.strava_gear_id
    assert_equal ["g2"], Gear.pluck(:strava_id)
    assert_nil @profile.reload.strava_gear_synced_at
  end

  test "without profile access nothing is requested" do
    @profile.update!(strava_scope: "read,activity:read_all")

    Activity.sync_strava_gear_now(full: true)
    Activity::StravaGearJob.perform_now

    assert_not_requested :get, /strava\.com/
    assert_nil @profile.reload.strava_gear_synced_at
  end

  test "a 401 clears the connection and the job swallows it" do
    stub_request(:get, /athlete\/activities/).to_return(status: 401, body: "{}")

    assert_nothing_raised { Activity::StravaGearJob.perform_now }

    assert_not @profile.reload.strava_connected?
  end

  test "the link scan reads gear ids and, when full, fetches the gear" do
    summaries({"id" => 555, "sport_type" => "Run", "start_date" => @run.started_at.iso8601, "gear_id" => "g1"})
    stub_request(:get, ATHLETE_URL).to_return(body: "{}")
    gear

    Activity.link_strava_now(full: true)

    assert_equal "g1", @run.reload.strava_gear_id
    assert_equal ["g1"], Gear.pluck(:strava_id)
  end

  test "the gear job is queued after a sync" do
    assert_enqueued_with(job: Activity::StravaGearJob, args: [{full: false}]) { Activity.sync_strava_gear_later }
  end
end
