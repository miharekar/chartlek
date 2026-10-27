class PaceZones
  COUNT = 37
  WALK_BELOW_KMH = 5.5
  STEP_KMH = 0.5
  ZOOM = COUNT - 1
  LOW_PERCENTILE = 0.25
  PADDING = 1

  class << self
    def zone_for(kmh)
      if kmh < WALK_BELOW_KMH
        0
      else
        [1 + ((kmh - WALK_BELOW_KMH) / STEP_KMH).floor, ZOOM].min
      end
    end

    def zone_for_vdot(vdot)
      zone_for(5.0 / Vdot.time_for(5000, vdot) * 3600)
    end

    def range(vdots, current)
      sorted = vdots.compact.sort

      if sorted.any?
        low = zone_for_vdot(sorted[((sorted.size - 1) * LOW_PERCENTILE).floor])
        high = zone_for_vdot(sorted.last)
      else
        low = high = current
      end

      [[low - PADDING, 0].max, current].min..[[high + PADDING, ZOOM].min, current].max
    end

    def label(zone)
      case zone
      when 0 then "walk"
      when ZOOM then "zoom"
      else
        seconds = (3600 / (WALK_BELOW_KMH + zone * STEP_KMH)).floor
        format("%d:%02d", seconds / 60, seconds % 60)
      end
    end
  end
end
