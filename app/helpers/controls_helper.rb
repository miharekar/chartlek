module ControlsHelper
  BASE = "inline-flex cursor-pointer items-center justify-center rounded-md px-3 text-sm font-medium tabular-nums focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-700 disabled:cursor-default disabled:opacity-50 aria-disabled:cursor-default aria-disabled:opacity-50 dark:focus-visible:outline-[#6ACD12]"
  SELECTED = "aria-pressed:bg-lime-700 aria-pressed:text-white aria-[current=page]:bg-lime-700 aria-[current=page]:text-white dark:aria-pressed:bg-[#6ACD12] dark:aria-pressed:text-zinc-950 dark:aria-[current=page]:bg-[#6ACD12] dark:aria-[current=page]:text-zinc-950"
  OUTLINE = "border border-zinc-300 text-zinc-700 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-900"
  BUTTON = "min-h-8 #{BASE} #{OUTLINE}"
  TOGGLE = "min-h-8 #{BASE} #{OUTLINE} #{SELECTED} aria-pressed:border-transparent dark:aria-pressed:border-transparent"
  GROUP = "flex min-h-8 w-fit max-w-full flex-wrap gap-0.5 rounded-lg bg-zinc-100 p-0.5 dark:bg-zinc-900"
  SEGMENT = "min-h-7 #{BASE} #{SELECTED} text-zinc-600 not-aria-pressed:not-aria-[current=page]:hover:bg-zinc-200 dark:text-zinc-400 dark:not-aria-pressed:not-aria-[current=page]:hover:bg-zinc-800"

  def button_group(label, &block)
    tag.div class: GROUP, role: "group", aria: {label:}, &block
  end

  def segment(text, selected: false, href: nil, **options)
    if href
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
