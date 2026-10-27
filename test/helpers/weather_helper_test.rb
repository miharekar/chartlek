require "test_helper"

class WeatherHelperTest < ActionView::TestCase
  DAY = {"temperature" => 14.2, "humidity" => 60.4, "wind" => 8.2, "precipitation" => 0, "code" => 2, "sunrise" => "2023-05-06T05:30", "sunset" => "2023-05-06T20:30"}

  def run_with(weather, at: Time.utc(2023, 5, 6, 7))
    build(:activity, local_started_at: at, timer_s: 1800, elapsed_s: 1800, weather:)
  end

  test "codes map to one condition and label" do
    {0 => [:clear, "Clear"], 1 => [:clear, "Clear"], 2 => [:partly_cloudy, "Partly cloudy"], 3 => [:cloudy, "Cloudy"], 45 => [:fog, "Fog"], 48 => [:fog, "Fog"],
     51 => [:drizzle, "Drizzle"], 57 => [:drizzle, "Drizzle"], 61 => [:rain, "Rain"], 67 => [:rain, "Rain"], 71 => [:snow, "Snow"], 77 => [:snow, "Snow"],
     80 => [:showers, "Showers"], 82 => [:showers, "Showers"], 85 => [:snow, "Snow"], 95 => [:thunderstorm, "Thunderstorm"], 99 => [:thunderstorm, "Thunderstorm"]}.each do |code, expected|
      assert_equal expected, weather_condition(code), "code #{code}"
    end
  end

  test "an unknown or missing code has no condition" do
    assert_nil weather_condition(42)
    assert_nil weather_condition(nil)
  end

  test "clear and partly cloudy turn to night variants, other conditions don't" do
    assert_equal [:clear_night, "Clear"], weather_condition(0, night: true)
    assert_equal [:partly_cloudy_night, "Partly cloudy"], weather_condition(2, night: true)
    assert_equal [:rain, "Rain"], weather_condition(61, night: true)
  end

  test "a run at night between sunset and sunrise gets the night icon" do
    day = run_weather(run_with(DAY))
    night = run_weather(run_with(DAY, at: Time.utc(2023, 5, 6, 22)))
    early = run_weather(run_with(DAY, at: Time.utc(2023, 5, 6, 3)))

    assert_includes day, "M5.25 1.5"
    assert_includes night, "M7.6 4.6"
    assert_includes early, "M7.6 4.6"
    assert_includes night, "Partly cloudy"
  end

  test "values keep their units and every icon is decorative" do
    html = run_weather(run_with(DAY.merge("precipitation" => 0.4)))

    ["Partly cloudy", "14°C", "60%", "8 km/h", "0.4 mm"].each { assert_includes html, it }
    %w[humidity wind rain].each { assert_includes html, %(<span class="sr-only">#{it} </span>) }
    assert_not_includes html.gsub(/<span class="sr-only">[^<]*<\/span>/, ""), "humidity"
    assert_equal 5, html.scan("<svg").size
    assert_equal 5, html.scan('aria-hidden="true"').size
  end

  test "nil fields and zero precipitation leave no item" do
    html = run_weather(run_with({"temperature" => 9.6, "code" => nil}))

    assert_includes html, "10°C"
    assert_equal 1, html.scan("<svg").size
    assert_not_includes html, "humidity"
    assert_not_includes html, "wind"
    assert_not_includes html, "rain"
  end

  test "missing or unreadable sun times count as day, and nothing is injected" do
    html = run_weather(run_with(DAY.merge("sunrise" => "<script>alert(1)</script>", "sunset" => nil), at: Time.utc(2023, 5, 6, 23)))

    assert_includes html, "M5.25 1.5"
    assert_not_includes html, "<script"
  end
end
