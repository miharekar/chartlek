module PaceTrendsHelper
  FILTERS = [["Exclude pauses", "no_pauses"], ["Exclude treadmill", "no_indoor"], ["Races only", "races"]].freeze
  PRESETS = [["3 mo", "3"], ["6 mo", "6"], ["1 yr", "12"], ["2 yr", "24"], ["All time", "all"]].freeze
  CARRIED_PARAMS = %w[no_pauses no_indoor races from to distance].freeze

  def pace_trend_filter_chips
    safe_join(FILTERS.map { |label, key|
      active = params[key] == "1"
      pace_trend_chip(label, pace_trend_path(pace_trend_query.merge(key => (active ? nil : "1")).compact), active)
    })
  end

  def pace_trend_presets
    tag.div class: "flex gap-1 rounded-lg bg-zinc-100 p-1 dark:bg-zinc-900", role: "group", aria: {label: "Window"} do
      safe_join(PRESETS.map { |label, key|
        tag.button label, type: "button", class: pr_progress_button_class, aria: {pressed: false}, data: {action: "pace-trends#preset", pace_trends_target: "preset", preset: key}
      })
    end
  end

  private
  def pace_trend_query
    request.query_parameters.slice(*CARRIED_PARAMS)
  end

  def pace_trend_chip(label, path, active)
    classes = if active
      "border-lime-700 bg-lime-100 text-lime-900 dark:border-[#6ACD12] dark:bg-lime-950 dark:text-[#9CFF44]"
    else
      "border-zinc-300 text-zinc-600 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-900"
    end

    link_to label, path, class: "rounded-full border px-3 py-1 text-xs font-medium #{classes}", aria: {pressed: active}, data: {turbo_action: "replace", pace_trends_target: "link"}
  end
end
