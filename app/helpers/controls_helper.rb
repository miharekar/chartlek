module ControlsHelper
  BASE = "inline-flex cursor-pointer items-center justify-center rounded-md text-sm tabular-nums disabled:cursor-default disabled:opacity-50 aria-disabled:cursor-default aria-disabled:opacity-50"
  SELECTED = "aria-pressed:bg-lime-700 aria-pressed:text-white aria-[current=page]:bg-lime-700 aria-[current=page]:text-white dark:aria-pressed:bg-[#6ACD12] dark:aria-pressed:text-zinc-950 dark:aria-[current=page]:bg-[#6ACD12] dark:aria-[current=page]:text-zinc-950"
  OUTLINE = "border border-zinc-300 text-zinc-700 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-900"
  BUTTON = "min-h-8 px-3 font-medium #{BASE} #{OUTLINE}"
  TOGGLE = "min-h-8 px-3 font-medium #{BASE} #{OUTLINE} #{SELECTED} aria-pressed:border-transparent dark:aria-pressed:border-transparent"
  INPUT = "min-h-8 rounded-md border border-zinc-300 bg-white px-3 text-sm tabular-nums dark:border-zinc-700 dark:bg-zinc-900"
  GROUP = "flex min-h-8 w-fit max-w-full flex-wrap gap-0.5 rounded-lg bg-zinc-100 p-0.5 dark:bg-zinc-900"
  IDLE = "text-zinc-600 dark:text-zinc-400"
  SEGMENT_LOOK = "#{SELECTED} #{IDLE} not-aria-pressed:not-aria-[current=page]:hover:bg-zinc-200 dark:not-aria-pressed:not-aria-[current=page]:hover:bg-zinc-800"
  SEGMENT = "min-h-7 px-3 font-medium #{BASE} #{SEGMENT_LOOK}"
  ICON_SEGMENT = "size-7 #{BASE} #{SEGMENT_LOOK}"
  DISABLED_SEGMENT = "min-h-7 px-3 font-medium #{BASE} #{IDLE}"
  INFO = "inline-flex size-4 shrink-0 cursor-help items-center justify-center rounded-full text-zinc-400 hover:text-zinc-700 focus-visible:text-zinc-700 dark:text-zinc-500 dark:hover:text-zinc-200 dark:focus-visible:text-zinc-200"
  INFO_ICON = '<svg viewBox="0 0 16 16" class="size-4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><circle cx="8" cy="8" r="6.75"/><path d="M8 7.25v3.5"/><circle cx="8" cy="4.9" r=".4" fill="currentColor"/></svg>'.html_safe.freeze

  def button_group(label, nav: false, &block)
    if nav
      tag.nav class: GROUP, aria: {label:}, &block
    else
      tag.div class: GROUP, role: "group", aria: {label:}, &block
    end
  end

  def segment(text, selected: false, href: nil, disabled: false, **options)
    if disabled
      tag.span text, class: DISABLED_SEGMENT, aria: {disabled: true}
    elsif href
      link_to text, href, class: SEGMENT, aria: {current: ("page" if selected)}, **options
    else
      tag.button text, type: "button", class: SEGMENT, aria: {pressed: selected}, **options
    end
  end

  def toggle_button(text, pressed: false, href: nil, **options)
    if href
      link_to text, href, class: TOGGLE, aria: {pressed:}, **options
    else
      tag.button text, type: "button", class: TOGGLE, aria: {pressed:}, **options
    end
  end

  def action_button(text, href, **options)
    link_to text, href, class: BUTTON, **options
  end
end
