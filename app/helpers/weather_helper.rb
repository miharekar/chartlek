module WeatherHelper
  LABELS = {
    clear: "Clear", partly_cloudy: "Partly cloudy", cloudy: "Cloudy", fog: "Fog", drizzle: "Drizzle",
    rain: "Rain", showers: "Showers", snow: "Snow", thunderstorm: "Thunderstorm"
  }.freeze
  NIGHT = {clear: :clear_night, partly_cloudy: :partly_cloudy_night}.freeze
  CLOUD = '<path d="M4.75 12.25a2.75 2.75 0 0 1-.3-5.48 4 4 0 0 1 7.6.9 2.3 2.3 0 0 1-.35 4.58Z"/>'.html_safe
  HIGH_CLOUD = '<path d="M4.75 9a2.75 2.75 0 0 1-.3-5.48 4 4 0 0 1 7.6.9 2.3 2.3 0 0 1-.35 4.58Z"/>'.html_safe
  SMALL_CLOUD = '<path d="M6.75 14a2.25 2.25 0 0 1-.2-4.49 3.25 3.25 0 0 1 6.2.75 1.9 1.9 0 0 1-.3 3.74Z"/>'.html_safe
  ICONS = {
    clear: ['<circle cx="8" cy="8" r="2.75"/><path d="M8 1.5v1.5M8 13v1.5M1.5 8H3M13 8h1.5M3.4 3.4l1 1M11.6 11.6l1 1M3.4 12.6l1-1M11.6 4.4l1-1"/>'.html_safe],
    clear_night: ['<path d="M13.5 9.5A5.75 5.75 0 0 1 6.5 2.5a5.75 5.75 0 1 0 7 7Z"/>'.html_safe],
    partly_cloudy: ['<circle cx="5.25" cy="5.25" r="1.9"/><path d="M5.25 1.5v.8M1.5 5.25h.8M2.6 2.6l.55.55M7.9 2.6l-.55.55"/>'.html_safe, SMALL_CLOUD],
    partly_cloudy_night: ['<path d="M7.6 4.6A3 3 0 0 1 3.4 1.6a3 3 0 1 0 4.2 3Z"/>'.html_safe, SMALL_CLOUD],
    cloudy: [CLOUD],
    fog: ['<path d="M2 5h12M3.5 8h9M2 11h12"/>'.html_safe],
    drizzle: [HIGH_CLOUD, '<path d="M5.5 11.5v.5M8 12.5v.5M10.5 11.5v.5"/>'.html_safe],
    rain: [HIGH_CLOUD, '<path d="M5.5 11l-.75 2.5M8.25 11l-.75 2.5M11 11l-.75 2.5"/>'.html_safe],
    showers: [HIGH_CLOUD, '<path d="M5.5 10.75l-1 3.5M8.5 10.75l-1 3.5M11.5 10.75l-1 3.5"/>'.html_safe],
    snow: [HIGH_CLOUD, '<path d="M5.5 11.5v.01M8 13.5v.01M10.5 11.5v.01M8 10.5v.01"/>'.html_safe],
    thunderstorm: [HIGH_CLOUD, '<path d="M8.5 9.5l-1.75 2.25h2.5L7.5 14"/>'.html_safe],
    temperature: ['<path d="M6.5 9.4V3.5a1.5 1.5 0 0 1 3 0v5.9a3 3 0 1 1-3 0Z"/>'.html_safe],
    humidity: ['<path d="M8 2s4 4.2 4 7a4 4 0 0 1-8 0c0-2.8 4-7 4-7Z"/>'.html_safe],
    wind: ['<path d="M2 6h7.5a2 2 0 1 0-2-2M2 9h10a2 2 0 1 1-2 2M2 12h4"/>'.html_safe],
    precipitation: ['<path d="M5.5 3.5l-1.25 4.5M9 3.5L7.75 8M12.5 3.5L11.25 8M4 10.5l-1.25 3M7.5 10.5l-1.25 3M11 10.5l-1.25 3"/>'.html_safe]
  }.freeze

  def weather_condition(code, night: false)
    kind = case code
    when 0, 1 then :clear
    when 2 then :partly_cloudy
    when 3 then :cloudy
    when 45, 48 then :fog
    when 51..57 then :drizzle
    when 61..67 then :rain
    when 71..77, 85, 86 then :snow
    when 80..82 then :showers
    when 95, 96, 99 then :thunderstorm
    end

    [(night ? NIGHT.fetch(kind, kind) : kind), LABELS[kind]] if kind
  end

  def run_weather(run)
    weather = run.weather
    night = weather_night?(weather, run.local_midpoint)
    condition = weather_condition(weather["code"], night:)
    items = [
      condition,
      (weather["temperature"] && [:temperature, "#{weather["temperature"].round}°C"]),
      (weather["humidity"] && [:humidity, "#{weather["humidity"].round}%", "humidity"]),
      (weather["wind"] && [:wind, "#{weather["wind"].round} km/h", "wind"]),
      (weather["precipitation"]&.positive? && [:precipitation, "#{weather["precipitation"]} mm", "rain"])
    ].compact_blank

    safe_join(items.map { |icon, text, word| tag.span(safe_join([weather_icon(icon), (tag.span("#{word} ", class: "sr-only") if word), text]), class: WidgetsHelper::META_ITEM) })
  end

  private
  def weather_icon(name)
    tag.svg(safe_join(ICONS.fetch(name)), viewBox: "0 0 16 16", class: "size-4 shrink-0", fill: "none", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round", aria: {hidden: true})
  end

  def weather_night?(weather, midpoint)
    sunrise = Time.zone.parse(weather["sunrise"].to_s)
    sunset = Time.zone.parse(weather["sunset"].to_s)

    sunrise.present? && sunset.present? && !midpoint.between?(sunrise, sunset)
  end
end
