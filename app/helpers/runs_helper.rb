module RunsHelper
  COLUMNS = [%w[Date date left], %w[Name name left], %w[km km right], %w[Time time right], %w[Pace pace right], %w[HR hr right], %w[Elev elevation right], %w[VDOT vdot right]].freeze
  GEAR_ICON = '<path d="M1.75 12.25V9.5c0-.5.3-.8.8-.9L5.25 8l1.25-2.75 1.5 1.1c.9.7 1.9 1.4 3.4 1.9 2.1.6 3.1 1.1 3.1 2.5v1.5Z"/><path d="M1.75 10.5h12.5M6.75 8.25l1-1.5"/>'.html_safe.freeze
  DAY = "inline-flex size-8 items-center justify-center rounded-md text-sm tabular-nums"
  DAY_STATES = {
    selected: "font-medium #{ControlsHelper::SELECTED}",
    idle: "text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800",
    weekend: "bg-zinc-100 text-zinc-800 hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-200 dark:hover:bg-zinc-700",
    race: "bg-amber-100 font-medium text-amber-800 hover:bg-amber-200 dark:bg-amber-900/40 dark:text-amber-300 dark:hover:bg-amber-900/70",
    disabled: "cursor-default text-zinc-300 dark:text-zinc-700"
  }.freeze

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

    tag.th class: "#{WidgetsHelper::CELL} font-medium text-#{align}", aria: {sort: (current == key) ? (descending ? "descending" : "ascending") : nil} do
      link = link_to "#{label}#{arrow}", runs_path(request.query_parameters.slice("year", "month", "gear").select { |_, value| value.is_a?(String) }.merge("sort" => key, "dir" => next_dir)), class: "hover:text-zinc-900 dark:hover:text-zinc-100"

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
      (chip("race", :race) if run.race),
      (chip("PR", :pr) if run.garmin_pr?),
      (chip("treadmill", :treadmill) if run.indoor)
    ].compact, " ")
  end

  def run_gear_tag(run)
    return unless sync_profile.strava_gear_ready?

    if run.strava_gear_id
      link_to run.gear&.display_name || run.strava_gear_id, runs_path(gear: run.strava_gear_id, year: "all"), class: [WidgetsHelper::CHIP, WidgetsHelper::CHIPS[:gear]]
    elsif run.strava_id
      link_to "No gear", runs_path(gear: "none", year: "all"), class: [WidgetsHelper::CHIP, WidgetsHelper::CHIPS[:no_gear]]
    end
  end

  def run_gear_line(run)
    tag.p safe_join([gear_icon, tag.span("Gear ", class: "sr-only"), run_gear_link(run)]), class: "mt-1 flex items-center gap-1.5 #{WidgetsHelper::HEADER_LINE}" if run.strava_id && sync_profile.strava_gear_ready?
  end

  def run_clock(run)
    finish = run.local_started_at + (run.elapsed_s || run.timer_s)
    "#{run.local_started_at.strftime("%H:%M")}–#{finish.strftime("%H:%M")}"
  end

  def run_gear_link(run)
    if run.strava_gear_id
      link_to run.gear&.display_name || run.strava_gear_id, runs_path(gear: run.strava_gear_id, year: "all"), class: WidgetsHelper::TABLE_LINK
    else
      link_to "No gear", runs_path(gear: "none", year: "all"), class: WidgetsHelper::WARNING
    end
  end

  def gear_icon
    tag.svg(GEAR_ICON, viewBox: "0 0 16 16", class: "size-4 shrink-0", fill: "none", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round", aria: {hidden: true})
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

  def run_effort_tiles(effort)
    intensity = [effort[:moderate], effort[:vigorous]].compact

    [
      (tile("Aerobic effect", format("%.1f", effort[:aerobic]), "/ 5", effort[:label]&.humanize&.sub("Vo2", "VO2")) if effort[:aerobic]),
      (tile("Anaerobic effect", format("%.1f", effort[:anaerobic]), "/ 5") if effort[:anaerobic]),
      (tile("Training load", effort[:load].round) if effort[:load]),
      (tile("Body Battery change", effort[:body_battery].negative? ? "−#{effort[:body_battery].abs}" : "+#{effort[:body_battery]}") if effort[:body_battery]),
      (tile("Intensity minutes", intensity.sum.round, "min", [("#{effort[:moderate]} moderate" if effort[:moderate]), ("#{effort[:vigorous]} vigorous" if effort[:vigorous])].compact.join(" · ")) if intensity.any?)
    ].compact
  end

  def run_dynamics(dynamics)
    [
      (["Ground contact", "#{dynamics[:ground_contact].round} ms"] if dynamics[:ground_contact]),
      (["Vertical oscillation", "#{format("%.1f", dynamics[:vertical_oscillation])} cm"] if dynamics[:vertical_oscillation]),
      (["Stride length", "#{(dynamics[:stride_length] / 100).round(2)} m"] if dynamics[:stride_length]),
      (["Vertical ratio", "#{format("%.1f", dynamics[:vertical_ratio])}%"] if dynamics[:vertical_ratio])
    ].compact
  end

  def run_going_in_tiles(going_in)
    baseline = "baseline #{going_in[:hrv_baseline_low]}–#{going_in[:hrv_baseline_high]} ms" if going_in[:hrv_baseline_low] && going_in[:hrv_baseline_high]

    [
      (tile("Resting HR", going_in[:resting_hr], "bpm", ("7-day average #{going_in[:resting_hr_avg_7d]} bpm" if going_in[:resting_hr_avg_7d])) if going_in[:resting_hr]),
      (tile("HRV last night", going_in[:hrv_last_night], "ms", [going_in[:hrv_status]&.humanize, baseline].compact.join(" · ")) if going_in[:hrv_last_night]),
      (tile("Sleep last night", format("%d:%02d", going_in[:sleep_s] / 3600, going_in[:sleep_s] % 3600 / 60), "h", ("score #{going_in[:sleep_score]}" if going_in[:sleep_score])) if going_in[:sleep_s]),
      (tile("Body Battery at wake", going_in[:body_battery_wake], "/ 100") if going_in[:body_battery_wake])
    ].compact
  end

  def run_zone_minutes(seconds)
    "#{(seconds / 60).round} min"
  end

  private
  def tile(label, value, unit = nil, sub = nil)
    {label:, value:, unit:, sub: sub.presence}
  end
end
