class Track < ApplicationRecord
  class Error < StandardError; end

  BAR_M = 100.0

  belongs_to :activity

  def bars(size = BAR_M)
    Metrics.new(Recording.new(rows)).splits(size)
  end

  def wheel_bars
    start = 0.0
    bars.filter_map do |bar|
      from = start
      start += bar[:distance]
      {from: (from / 1000).round(3), to: (start / 1000).round(3), distance: bar[:distance], time: bar[:time]} if bar[:distance] >= BAR_M && bar[:time].positive?
    end
  end

  def steps
    chart_metrics&.dig("steps")
  end

  def efforts
    Efforts.new(data).all
  end

  def mappable?
    route.size > 1
  end

  def route
    data.fetch("lng", []).zip(data.fetch("lat", [])).reject { it.include?(nil) }
  end

  def route_distances
    data.fetch("d", []).zip(data.fetch("lng", []), data.fetch("lat", [])).reject { it.drop(1).include?(nil) }.map(&:first)
  end

  private
  def rows
    keys = data.keys.map(&:to_sym)
    data.values.transpose.map { keys.zip(it).to_h }
  end
end
