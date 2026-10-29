module OverviewsHelper
  VDOT_EXAMPLES = [45, 50].freeze

  def overview_pace(seconds)
    total = seconds.round
    format("%d:%02d", total / 60, total % 60)
  end

  def overview_duration(seconds)
    total = seconds.round
    hours, rest = total.divmod(3600)

    if hours.positive?
      format("%d:%02d:%02d", hours, rest / 60, rest % 60)
    else
      format("%d:%02d", rest / 60, rest % 60)
    end
  end

  def overview_distance(km)
    format("%.1f", km)
  end

  def overview_date(date)
    date.to_date.strftime("%-d %b %Y")
  end

  def overview_range(from, to)
    if from == to
      overview_date(from)
    else
      "#{overview_date(from)} – #{overview_date(to)}"
    end
  end

  def goal_tile_span(tiles)
    tiles.size > 1 ? "col-span-2 lg:col-span-1" : "col-span-2"
  end

  def overview_period_title(period)
    case period.kind
    when :month then Date.new(period.year, period.month, 1).strftime("%B %Y")
    when :year then period.year.to_s
    else "All time"
    end
  end

  def vdot_explanation
    examples = VDOT_EXAMPLES.map { |vdot|
      times = PaceTrend::DISTANCES.map { |label, meters| "#{label.match?(/\d/) ? label : label.downcase} #{overview_duration(Vdot.time_for(meters, vdot))}" }
      "VDOT #{vdot} ≈ #{times.join(", ")}."
    }

    "VDOT is Jack Daniels' estimate of the VO2max a run implies, on the same scale as your watch's VO2max. It puts every distance on one scale, and one point is worth about 2% of race time. Easy runs score lower because they aren't all-out. #{examples.join(" ")}"
  end

  def vdot_info
    overview_info vdot_explanation
  end

  def overview_info(text)
    tag.button ControlsHelper::INFO_ICON, type: "button", class: ControlsHelper::INFO, aria: {label: text}, data: {controller: "info", action: "mouseenter->info#show mouseleave->info#leave focus->info#show blur->info#hide click->info#toggle keydown.esc@window->info#hide click@document->info#outside"}
  end
end
