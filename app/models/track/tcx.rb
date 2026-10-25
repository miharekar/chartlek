class Track::Tcx
  PAUSE_GAP_S = 10
  STILL_MPS = 0.5

  def self.parse(xml)
    new(xml).recording
  end

  def initialize(xml)
    @doc = Nokogiri::XML(xml).remove_namespaces!
  end

  def recording
    previous = nil
    timer = 0.0

    rows = @doc.xpath("//Lap").flat_map do |lap|
      points = lap.xpath("Track/Trackpoint").map { [Time.iso8601(it.at_xpath("Time").text).to_f, row(it)] }
      removed = removals(lap, points, previous)

      points.each_with_index.map do |(at, row), index|
        gap = previous ? at - previous : 0.0
        timer += gap - removed.fetch(index, 0.0) unless index.zero? && gap > PAUSE_GAP_S
        previous = at

        row.merge(t: timer)
      end
    end

    Track::Recording.new(rows)
  end

  private
  def removals(lap, points, previous)
    total = lap.at_xpath("TotalTimeSeconds")&.text&.to_f
    excess = total && points.any? ? added(points, previous) - total : 0.0

    stalls(points).sort_by { -it.last }.each_with_object({}) do |(index, gap), removed|
      removed[index] = [gap, excess].min if excess.positive?
      excess -= gap
    end
  end

  def added(points, previous)
    lead = previous ? points.first.first - previous : 0.0

    points.last.first - points.first.first + (lead > PAUSE_GAP_S ? 0.0 : lead)
  end

  def stalls(points)
    points.each_cons(2).each_with_index.filter_map do |((from, before), (to, after)), index|
      [index + 1, to - from] if to - from > PAUSE_GAP_S && before[:d] && after[:d] && (after[:d] - before[:d]) / (to - from) < STILL_MPS
    end
  end

  def row(point)
    {
      d: number(point, "DistanceMeters"),
      lat: number(point, "Position/LatitudeDegrees"),
      lng: number(point, "Position/LongitudeDegrees"),
      alt: number(point, "AltitudeMeters"),
      hr: number(point, "HeartRateBpm/Value"),
      cad: number(point, "Extensions/TPX/RunCadence")&.*(2)
    }
  end

  def number(point, path)
    point.at_xpath(path)&.text&.to_f
  end
end
