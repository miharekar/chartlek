module WidgetsHelper
  CARD = "rounded-xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-900/50"
  CARD_HEADER = "flex flex-wrap items-center justify-between gap-2"
  CARD_TITLE = "flex items-center gap-1.5 font-semibold"
  PAGE_HEADER = "flex flex-wrap items-start justify-between gap-4"
  PAGE_TITLE = "flex items-center gap-2 text-2xl font-semibold"
  MUTED = "text-zinc-500 dark:text-zinc-400"
  TILE_LABEL = "text-sm font-medium #{MUTED}"
  TILE_VALUE = "mt-1 text-4xl font-semibold tabular-nums"
  TILE_UNIT = "ml-1 text-sm font-normal #{MUTED}"
  TILE_SUB = "mt-1 text-sm tabular-nums text-zinc-600 dark:text-zinc-300"
  HINT = "text-xs #{MUTED}"
  HEADER_LINE = "text-sm tabular-nums text-zinc-600 dark:text-zinc-300"
  META = "flex flex-wrap items-center gap-x-4 gap-y-1 #{HEADER_LINE}"
  META_ITEM = "inline-flex items-center gap-1.5"
  LEGEND = "flex flex-wrap items-center gap-x-4 gap-y-1 #{HINT}"
  WARNING = "font-medium text-amber-700 hover:underline dark:text-amber-300"
  PLACEHOLDER = "text-zinc-400"
  ACCENT = "text-lime-700 dark:text-[#9CFF44]"
  LINK = "underline decoration-zinc-300 hover:text-lime-700 dark:decoration-zinc-600 dark:hover:text-[#9CFF44]"
  EMPTY = "rounded-xl border border-zinc-200 p-10 text-center dark:border-zinc-800"
  TABLE = "w-full text-sm tabular-nums"
  TABLE_HEAD = "text-zinc-500 dark:text-zinc-400"
  TABLE_HEAD_ROW = "border-b border-zinc-200 dark:border-zinc-800"
  TABLE_BODY = "divide-y divide-zinc-100 dark:divide-zinc-800/60"
  TABLE_ROW = "hover:bg-zinc-50 dark:hover:bg-zinc-800/40"
  CELL = "px-3 py-2"
  TABLE_LINK = "hover:text-lime-700 hover:underline dark:hover:text-[#9CFF44]"
  CHIP = "rounded px-1.5 py-0.5 text-xs font-medium"
  CHIPS = {
    race: "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300",
    pr: "bg-lime-100 text-lime-900 dark:bg-lime-900/30 dark:text-lime-300",
    treadmill: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-300",
    notable: "bg-lime-100 text-lime-900 dark:bg-lime-900/30 dark:text-lime-300",
    gear: "bg-zinc-100 text-zinc-600 hover:text-lime-700 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:text-[#9CFF44]",
    no_gear: "bg-amber-100 text-amber-800 hover:bg-amber-200 dark:bg-amber-900/40 dark:text-amber-300 dark:hover:bg-amber-900/70"
  }.freeze

  def page_header(title, info: nil, &block)
    tag.div class: PAGE_HEADER do
      safe_join([tag.h1(safe_join([title, info].compact), class: PAGE_TITLE), (capture(&block) if block)].compact)
    end
  end

  def empty_state(title, &block)
    action = capture(&block) if block

    tag.div class: "mt-6 #{EMPTY}" do
      safe_join([tag.p(title, class: "text-lg font-medium"), (tag.p(action, class: "mt-2 text-sm #{MUTED}") if action.present?)].compact)
    end
  end

  def chip(text, kind)
    tag.span text, class: [CHIP, CHIPS.fetch(kind)]
  end
end
