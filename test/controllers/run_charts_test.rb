require "test_helper"

class RunChartsTest < ActionDispatch::IntegrationTest
  setup do
    @token = ENV["MAPBOX_TOKEN"]
    ENV["MAPBOX_TOKEN"] = "pk.test"
  end

  teardown { ENV["MAPBOX_TOKEN"] = @token }

  def run_with(data, **attrs)
    run = create(:activity, **attrs)
    Track.create!(activity: run, data:) if data
    run
  end

  def full
    {"t" => [0, 30, 60, 90], "d" => [0, 100, 200, 250], "lat" => [46.0, 46.001, nil, 46.003], "lng" => [14.0, 14.001, nil, 14.003], "alt" => [300, 301, 302, 303], "hr" => [140, 150, 160, 170], "cad" => [170, 172, 174, 176]}
  end

  test "show renders speed, profiles and map for a full track" do
    run = run_with(full, splits: [{"distance" => 250.0, "time" => 90.0, "pace" => 360.0, "hr" => 155, "cad" => 173, "gain" => 3.0, "loss" => 0.0}])

    get run_path(run)

    assert_response :success
    assert_select "[data-controller=run-speed]"
    assert_select "[role=group][aria-label='Bar size'] button[value=bars][aria-pressed=true]", text: "per 100 m"
    assert_select "[role=group][aria-label='Bar size'] button[value=splits][aria-pressed=false]", text: "per km"
    assert_equal %w[run-map run-speed run-profiles], css_select("[data-controller]").map { it["data-controller"] }.select { %w[run-map run-speed run-profiles].include?(it) }
    assert_select "[data-controller=run-profiles]"
    assert_select "[data-controller=run-map][data-run-map-route-value=?]", "[[14.0,46.0],[14.001,46.001],[14.003,46.003]]"
    assert_select "[data-controller=run-map][data-run-map-token-value=?]", "pk.test"
  end

  test "show renders an indoor track without the map" do
    run = run_with({"t" => [0, 30, 60], "d" => [0, 100, 200], "hr" => [140, 150, 160]}, indoor: true, splits: [{"distance" => 200.0, "time" => 60.0, "pace" => 300.0}])

    get run_path(run)

    assert_response :success
    assert_select "[data-controller=run-speed]"
    assert_select "[data-controller=run-profiles]"
    assert_select "[data-controller=run-map]", false
  end

  test "show omits the speed chart when splits are nil, as for a rebuilt distance" do
    run = run_with(full)

    get run_path(run)

    assert_response :success
    assert_select "[data-controller=run-speed]", false
    assert_select "[data-controller=run-profiles]"
    assert_select "[data-controller=run-map]"
  end

  test "show omits the map unless the token is a public one" do
    run = run_with(full)

    ["", nil, "sk.test"].each do |token|
      ENV["MAPBOX_TOKEN"] = token
      get run_path(run)

      assert_response :success
      assert_select "[data-controller=run-map]", false
      assert_select "[data-controller=run-profiles]"
    end
  end

  test "show omits the profiles when no series exists" do
    run = run_with({"t" => [0, 30, 60], "d" => [0, 100, 200]}, splits: [{"distance" => 200.0, "time" => 60.0, "pace" => 300.0}])

    get run_path(run)

    assert_select "[data-controller=run-speed]"
    assert_select "[data-controller=run-profiles]", false
  end

  test "show renders no chart sections without a track" do
    run = run_with(nil)

    get run_path(run)

    assert_response :success
    assert_select "[data-controller=run-speed]", false
    assert_select "[data-controller=run-profiles]", false
    assert_select "[data-controller=run-map]", false
  end
end
