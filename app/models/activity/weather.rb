module Activity::Weather
  extend ActiveSupport::Concern

  class_methods do
    def weatherable
      where(indoor: false).where.not(start_lat: nil).where.not(start_lng: nil)
    end

    def fetch_weather(client: OpenMeteo::Client.new)
      report = {fetched: 0, pending: 0, skipped: count - weatherable.count, failed: {}}
      missing = weatherable.where(weather: nil).order(:local_started_at)
      total = missing.count

      missing.each_with_index do |run, index|
        begin
          run.fetch_weather(client)
          report[run.weather ? :fetched : :pending] += 1
        rescue => error
          report[:failed][run.external_id] = error.message
        end

        yield(done: index + 1, total:) if block_given?
      end

      report
    end
  end

  def weatherable?
    !indoor? && start_lat.present? && start_lng.present?
  end

  def fetch_weather(client = OpenMeteo::Client.new)
    if weatherable?
      midpoint = local_midpoint
      data = client.weather(lat: start_lat, lng: start_lng, date: midpoint.to_date)

      update!(weather: weather_at(data, midpoint))
    end
  end

  private
  def local_midpoint
    local_started_at + (elapsed_s || timer_s) / 2
  end

  def weather_at(data, midpoint)
    hourly = data["hourly"]
    index = hourly["time"].index(midpoint.strftime("%Y-%m-%dT%H:00"))

    if index && hourly["temperature_2m"][index]
      {
        "temperature" => hourly["temperature_2m"][index],
        "humidity" => hourly["relative_humidity_2m"][index],
        "wind" => hourly["wind_speed_10m"][index],
        "precipitation" => hourly["precipitation"][index],
        "code" => hourly["weather_code"][index],
        "sunrise" => data["daily"]["sunrise"].first,
        "sunset" => data["daily"]["sunset"].first
      }
    end
  end
end
