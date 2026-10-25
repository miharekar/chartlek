module RunsHelper
  COLUMNS = [%w[Date date left], %w[Name name left], %w[km km right], %w[Time time right], %w[Pace pace right], %w[HR hr right], %w[Elev elevation right], %w[SPI spi right], %w[VDOT vdot right]].freeze
  TAG = "rounded px-1.5 py-0.5 text-xs font-medium"

  def runs_period_title(year, month)
    if year && month
      Date.new(year, month, 1).strftime("%B %Y")
    else
      year&.to_s || "All time"
    end
  end

  def runs_sort_header(label, key, align)
    current = params[:sort].presence_in(Activity::SORTS.keys) || "date"
    descending = params[:dir] != "asc"
    arrow = if current != key
      ""
    elsif descending
      " ↓"
    else
      " ↑"
    end
    next_dir = (current == key && descending) ? "asc" : "desc"

    tag.th class: "px-3 py-2 font-medium text-#{align}", aria: {sort: (current == key) ? (descending ? "descending" : "ascending") : nil} do
      link_to "#{label}#{arrow}", runs_path(request.query_parameters.slice("year", "month").merge("sort" => key, "dir" => next_dir)), class: "hover:text-zinc-900 dark:hover:text-zinc-100"
    end
  end

  def run_tags(run)
    safe_join([
      (tag.span("race", class: "#{TAG} bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300") if run.race),
      (tag.span("treadmill", class: "#{TAG} bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-300") if run.indoor)
    ].compact, " ")
  end

  def run_clock(run)
    finish = run.local_started_at + (run.elapsed_s || run.timer_s)
    "#{run.local_started_at.strftime("%H:%M")}–#{finish.strftime("%H:%M")}"
  end

  def run_weather(weather)
    parts = [
      (weather["temperature"] && "#{weather["temperature"].round}°C"),
      (weather["humidity"] && "#{weather["humidity"].round}% humidity"),
      (weather["wind"] && "wind #{weather["wind"].round} km/h"),
      (weather["precipitation"]&.positive? && "#{weather["precipitation"]} mm rain")
    ]

    parts.compact_blank.join(" · ")
  end

  def run_extent(run, series, fallback_max)
    values = run.track&.data&.dig(series)&.compact

    if values.present?
      "#{values.min}–#{values.max}"
    elsif fallback_max
      "max #{fallback_max.round}"
    end
  end

  def run_variability_glyph(percent)
    amplitude = [percent * 0.4, 7.0].min
    points = (0...60).map { |index|
      angle = index * 2 * Math::PI / 60
      radius = 16 + amplitude * (Math.sin(5 * angle) + 0.5 * Math.sin(11 * angle + 1)) / 1.5
      format("%.1f,%.1f", 24 + radius * Math.cos(angle), 24 + radius * Math.sin(angle))
    }

    tag.svg viewBox: "0 0 48 48", class: "size-12 shrink-0", role: "img", aria: {label: "Pace variability #{percent.round(1)}%"} do
      tag.polygon points: points.join(" "), fill: "none", "stroke-width": 2, "stroke-linejoin": "round", style: "stroke: var(--chart-accent)"
    end
  end

  def run_rank_strip(rank, total)
    x = (total > 1) ? 4 + 112.0 * (rank - 1) / (total - 1) : 60

    tag.svg viewBox: "0 0 120 12", class: "mt-2 h-3 w-full max-w-48", role: "img", aria: {label: "Rank #{rank} of #{total}"} do
      tag.line(x1: 4, x2: 116, y1: 6, y2: 6, "stroke-width": 2, "stroke-linecap": "round", style: "stroke: var(--chart-grid)") +
        tag.circle(cx: x.round(1), cy: 6, r: 4, style: "fill: var(--chart-highlight)")
    end
  end

  def run_sparkline(profile)
    paces = Array(profile).compact

    if paces.size > 1
      fastest, slowest = paces.minmax
      span = (slowest - fastest).nonzero? || 1
      points = paces.each_with_index.map { |pace, index| format("%.1f,%.1f", 60.0 * index / (paces.size - 1), 2 + 16 * (pace - fastest) / span) }

      tag.svg viewBox: "0 0 60 20", class: "h-5 w-15", role: "img", aria: {label: "Pace profile"} do
        tag.polyline points: points.join(" "), fill: "none", "stroke-width": 1.5, "stroke-linejoin": "round", style: "stroke: var(--chart-accent)"
      end
    end
  end
end
