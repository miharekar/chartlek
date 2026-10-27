require "test_helper"

class MapsControllerTest < ActionDispatch::IntegrationTest
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
    {"t" => [0, 30, 60, 90, 120, 150], "d" => [0, 100, 200, 300, 400, 500], "lat" => [46.0, 46.001, 46.002, 46.003, 46.004, 46.005], "lng" => [14.0, 14.001, 14.002, 14.003, 14.004, 14.005], "alt" => [300, 301, 302, 303, 304, 305], "hr" => [140, 150, 160, 170, 175, 180], "cad" => [170, 172, 174, 176, 176, 176]}
  end

  def splits
    [{"distance" => 500.0, "time" => 150.0, "pace" => 300.0, "hr" => 160, "cad" => 174, "gain" => 5.0, "loss" => 0.0}]
  end

  test "show renders every metric, the efforts and the splits" do
    run = run_with(full, splits:, avg_hr: 160, max_hr: 190)

    get run_map_path(run)

    assert_response :success
    assert_select "[data-controller=pro-map][data-pro-map-token-value=?]", "pk.test"
    assert_equal %w[Pace HR Grade Cadence], css_select("[role=group][aria-label='Colour route by'] button").map { it.text.strip }
    assert_select "[role=group][aria-label='Colour route by'] button[value=pace][aria-pressed=true]"
    assert_select "[data-pro-map-target=range]", 3
    assert_select "[data-pro-map-target=graph]"
    assert_select "[data-pro-map-target=splits]"
  end

  test "show gives the map the run's own zone floors" do
    run = run_with(full, splits:, avg_hr: 160, hr_zones: {"floors" => [91, 111, 131, 151, 171], "max_hr" => 190, "source" => "fit"})

    get run_map_path(run)

    assert_select "[data-controller=pro-map][data-pro-map-floors-value=?]", "[91,111,131,151,171]"
  end

  test "show hides the metrics a run lacks and what needs splits" do
    run = run_with(full.slice("t", "d", "lat", "lng"))

    get run_map_path(run)

    assert_response :success
    assert_select "[role=group][aria-label='Colour route by']", false
    assert_select "[data-pro-map-target=graph]", false
    assert_select "[data-pro-map-target=range]", false
    assert_select "[data-pro-map-target=map]"
  end

  test "show redirects a run without a route or without the public token" do
    indoor = run_with({"t" => [0, 30], "d" => [0, 100]})
    run = run_with(full)
    ENV["MAPBOX_TOKEN"] = "sk.secret"

    get run_map_path(indoor)
    assert_redirected_to run_path(indoor)

    get run_map_path(run)
    assert_redirected_to run_path(run)
  end

  test "run page links to the pro map only with a route" do
    run = run_with(full)
    indoor = run_with({"t" => [0, 30], "d" => [0, 100]}, indoor: true)

    get run_path(run)
    assert_select "a[href=?]", run_map_path(run), text: "Open Pro Map"

    get run_path(indoor)
    assert_select "a", text: "Open Pro Map", count: 0
  end
end
