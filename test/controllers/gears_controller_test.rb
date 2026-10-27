require "test_helper"

class GearsControllerTest < ActionDispatch::IntegrationTest
  def connect(scope: "read,activity:read_all,profile:read_all", synced: true)
    profile = Profile.instance
    profile.store_strava_tokens(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
    profile.update!(strava_scope: scope, strava_gear_synced_at: (Time.current if synced))
  end

  def run_for(gear_id, at, **attrs)
    create(:activity, started_at: at, local_started_at: at, strava_id: rand(1_000_000) + 1, strava_gear_id: gear_id, **attrs)
  end

  test "without gear access it asks for a reconnect and lists nothing" do
    connect(scope: "read,activity:read_all")
    run_for(nil, Time.utc(2026, 10, 1))

    get gears_path

    assert_response :success
    assert_select "p", text: /needs Strava profile access/
    assert_select "table", false
    assert_select "form[action=?]", gear_sync_path, false
  end

  test "before the first scan it says so instead of listing runs as unset" do
    connect(synced: false)
    run_for(nil, Time.utc(2026, 10, 1))

    get gears_path

    assert_select "p", text: /first gear scan is pending/
    assert_select "table", false
    assert_select "form[action=?] button", gear_sync_path, text: "Refresh from Strava"
  end

  test "after the retries are used up it says the first scan failed and points to Refresh" do
    connect(synced: false)
    Profile.instance.update!(strava_gear_attempts: Profile::STRAVA_GEAR_ATTEMPTS)

    get gears_path

    assert_select "p", text: /first gear scan failed/
    assert_select "p", text: /first gear scan is pending/, count: 0
    assert_select "form[action=?] button", gear_sync_path, text: "Refresh from Strava"
  end

  test "lists gear most used first with the no gear row" do
    connect
    Gear.create!(strava_id: "g1", name: "Synthetic One", brand_name: "Acme", model: "Zoom")
    Gear.create!(strava_id: "g2", name: "Synthetic Two")
    run_for("g1", Time.utc(2026, 10, 1))
    run_for("g1", Time.utc(2026, 10, 2))
    run_for("g2", Time.utc(2026, 10, 3))
    run_for(nil, Time.utc(2026, 10, 4))

    get gears_path

    assert_response :success
    assert_select "tbody tr:nth-child(1) td:first-child", text: /Synthetic One/
    assert_select "tbody tr:nth-child(1) td:first-child", text: /Acme Zoom/
    assert_select "tbody tr:nth-child(2) td:first-child", text: /Synthetic Two/
    assert_select "tbody tr.bg-amber-50 a[href=?]", runs_path(gear: "none", year: "all"), text: "No gear set"
    assert_select "[data-controller=gear-charts] button[data-gear-charts-target=toggle]", 2
  end

  test "retired gear sits under a collapsed toggle and starts off in the charts" do
    connect
    Gear.create!(strava_id: "g1", name: "Old Pair", retired: true)
    Gear.create!(strava_id: "g2", name: "Current")
    run_for("g1", Time.utc(2026, 10, 1))
    run_for("g2", Time.utc(2026, 10, 2))

    get gears_path

    assert_select "[data-controller=disclosure] button", text: "Retired (1)"
    assert_select "[data-disclosure-target=panel][hidden] a", text: "Old Pair"
    assert_select "button[data-id=g1][aria-pressed=false]"
    assert_select "button[data-id=g2][aria-pressed=true]"
  end

  test "dead gear is listed by id with its label" do
    connect
    Gear.create!(strava_id: "g0", synced_at: Time.current)
    run_for("g0", Time.utc(2026, 10, 1))

    get gears_path

    assert_select "td a", text: "g0"
    assert_select "td p", text: "Gear no longer on Strava"
  end

  test "the page uses a handful of queries" do
    connect
    Gear.create!(strava_id: "g1", name: "One")
    5.times { |index| run_for("g1", Time.utc(2026, 10, 1) + index.days) }
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get gears_path }

    assert_operator count, :<=, 16
  end
end
