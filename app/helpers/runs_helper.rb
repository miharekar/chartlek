module RunsHelper
  COLUMNS = [%w[Date date left], %w[Name name left], %w[km km right], %w[Time time right], %w[Pace pace right], %w[HR hr right], %w[Elev elevation right], %w[VDOT vdot right]].freeze
  DAY = "inline-flex size-8 items-center justify-center rounded-md text-sm tabular-nums"
  DAY_STATES = {
    selected: OverviewsHelper::PILL_STATES[:selected],
    idle: "text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800",
    weekend: "bg-zinc-100 text-zinc-800 hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-200 dark:hover:bg-zinc-700",
    race: "bg-amber-100 font-medium text-amber-800 hover:bg-amber-200 dark:bg-amber-900/40 dark:text-amber-300 dark:hover:bg-amber-900/70",
    disabled: OverviewsHelper::PILL_STATES[:disabled]
  }.freeze
  TAG = "rounded px-1.5 py-0.5 text-xs font-medium"

  def runs_period_title(year, month)
    if year && month
      Date.new(year, month, 1).strftime("%B %Y")
    else
      year&.to_s || "All time"
    end
  end

  def runs_sort_header(label, key, align, info: false)
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
      link = link_to "#{label}#{arrow}", runs_path(request.query_parameters.slice("year", "month").merge("sort" => key, "dir" => next_dir)), class: "hover:text-zinc-900 dark:hover:text-zinc-100"

      if info
        tag.span safe_join([link, vdot_info]), class: "inline-flex items-center gap-1"
      else
        link
      end
    end
  end

  def run_calendar_day(day, current)
    date = day[:date]
    weekend = date.saturday? || date.sunday?

    if day[:id]
      state = if date == current.local_started_at.to_date then :selected
      elsif day[:race] then :race
      elsif weekend then :weekend
      else :idle
      end
      text = "#{date.strftime("%A, %-d %B %Y")} · #{overview_distance(day[:km])} km#{" · race" if day[:race]}"
      classes = [DAY, DAY_STATES.fetch(state)]
      classes << "ring-2 ring-amber-500" if day[:race] && state == :selected

      link_to date.day, run_path(day[:id]), class: classes, aria: {label: text, current: (state == :selected) ? "page" : nil}, data: {controller: "day-tip", day_tip_text_value: text, action: "pointerenter->day-tip#hover pointerleave->day-tip#hide focus->day-tip#focus blur->day-tip#hide"}
    else
      tag.span date.day, class: [DAY, DAY_STATES[:disabled], ("bg-zinc-50 dark:bg-zinc-900/50" if weekend)]
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

  def run_finishes(run)
    PaceTrend::DISTANCES.zip(run.finish_times).map { |(label, meters), (_, seconds)| {label:, km: meters / 1000.0, seconds:} }
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
