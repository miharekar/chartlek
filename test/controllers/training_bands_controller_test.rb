require "test_helper"

class TrainingBandsControllerTest < ActionDispatch::IntegrationTest
  test "shows an empty state without bands" do
    get training_bands_path

    assert_response :success
    assert_select "p", "No training bands yet."
    assert_select "[data-controller='training-bands']", false
    assert_select "code", "docker compose exec chartlek bin/rails activities:bands"
  end

  test "renders the chart payload and controls" do
    create(:activity, local_started_at: Time.utc(2024, 3, 5, 7), bands: {"pace" => [100] + [0] * 36, "hr" => [0, 0, 60, 0, 0], "grade" => nil})
    create(:activity, local_started_at: Time.utc(2024, 3, 20, 7), bands: {"pace" => [0, 50] + [0] * 35, "hr" => nil, "grade" => [0, 0, 0, 50, 0, 0, 0]})

    get training_bands_path, params: {category: "hr", view: "percent"}

    assert_response :success
    payload = JSON.parse(css_select("[data-controller='training-bands']").first["data-training-bands-payload-value"])
    assert_equal 3, payload["weeks"]
    assert_equal %w[pace hr grade], payload["categories"].keys
    assert_equal [100, 0, 0], payload["categories"]["pace"]["bands"]["0"]
    assert_equal "hr", payload["category"]
    assert_equal "percent", payload["view"]
    assert_select "button[aria-pressed='true'][data-value='hr']"
    assert_select "button[aria-pressed='true'][data-value='percent']"
    assert_select "div[data-category='pace'][hidden]"
  end

  test "falls back to pace when the requested category has no data" do
    create(:activity, bands: {"pace" => [100] + [0] * 36, "hr" => nil, "grade" => nil})

    get training_bands_path, params: {category: "hr"}

    assert_response :success
    payload = JSON.parse(css_select("[data-controller='training-bands']").first["data-training-bands-payload-value"])
    assert_equal "pace", payload["category"]
    assert_equal %w[pace], payload["categories"].keys
    assert_select "button[aria-pressed='true'][data-value='pace']"
  end

  test "leaves out a category no run has" do
    create(:activity, bands: {"pace" => [100] + [0] * 36, "hr" => nil, "grade" => nil})

    get training_bands_path, params: {category: "bogus", from: "nope"}

    assert_response :success
    assert_select "button[data-value='hr']", false
    assert_select "button[aria-pressed='true'][data-value='pace']"
  end
end
