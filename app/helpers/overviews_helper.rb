module OverviewsHelper
  PILL = "rounded-md px-2.5 py-1 text-sm tabular-nums"
  INFO = "inline-flex size-4 shrink-0 cursor-help items-center justify-center rounded-full text-zinc-400 hover:text-zinc-700 focus-visible:text-zinc-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-700 dark:text-zinc-500 dark:hover:text-zinc-200 dark:focus-visible:text-zinc-200 dark:focus-visible:outline-[#6ACD12]"
  INFO_ICON = '<svg viewBox="0 0 16 16" class="size-4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><circle cx="8" cy="8" r="6.75"/><path d="M8 7.25v3.5"/><circle cx="8" cy="4.9" r=".4" fill="currentColor"/></svg>'.html_safe.freeze
  PILL_STATES = {
    selected: "bg-lime-700 font-medium text-white dark:bg-[#6ACD12] dark:text-zinc-950",
    idle: "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800",
    disabled: "cursor-default text-zinc-300 dark:text-zinc-700"
  }.freeze

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

  def overview_period_title(period)
    case period.kind
    when :month then Date.new(period.year, period.month, 1).strftime("%B %Y")
    when :year then period.year.to_s
    else "All time"
    end
  end

  def overview_pill(label, path, state)
    classes = [PILL, PILL_STATES.fetch(state)]

    if state == :disabled
      tag.span label, class: classes
    else
      link_to label, path, class: classes
    end
  end

  def overview_info(text)
    tag.button INFO_ICON, type: "button", class: INFO, aria: {label: text}, data: {controller: "info", action: "mouseenter->info#show mouseleave->info#leave focus->info#show blur->info#hide click->info#toggle keydown.esc@window->info#hide click@document->info#outside"}
  end
end
