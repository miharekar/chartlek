module ApplicationHelper
  THEME_ICONS = {
    "system" => '<rect x="2" y="3" width="12" height="8.5" rx="1.5"/><path d="M5.5 14h5M8 11.5V14"/>'.html_safe,
    "light" => '<circle cx="8" cy="8" r="2.75"/><path d="M8 1.5v1.5M8 13v1.5M1.5 8H3M13 8h1.5M3.4 3.4l1 1M11.6 11.6l1 1M3.4 12.6l1-1M11.6 4.4l1-1"/>'.html_safe,
    "dark" => '<path d="M13.5 9.5A5.75 5.75 0 0 1 6.5 2.5a5.75 5.75 0 1 0 7 7Z"/>'.html_safe
  }.freeze

  def theme_switch
    tag.div class: "flex items-center gap-0.5 rounded-md border border-zinc-300 p-0.5 dark:border-zinc-700", role: "group", aria: {label: "Theme"} do
      safe_join(ThemesController::THEMES.map { |theme|
        button_to theme_path, method: :patch, params: {theme:}, form: {class: "contents", data: {turbo: false}}, title: theme.capitalize, aria: {label: theme.capitalize, pressed: current_theme == theme},
          class: "inline-flex size-6 cursor-pointer items-center justify-center rounded text-zinc-500 hover:text-zinc-900 aria-pressed:bg-zinc-200 aria-pressed:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100 dark:aria-pressed:bg-zinc-800 dark:aria-pressed:text-zinc-100" do
          tag.svg(THEME_ICONS.fetch(theme), viewBox: "0 0 16 16", class: "size-4", fill: "none", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round", aria: {hidden: true})
        end
      })
    end
  end

  def nav_link_to(name, path)
    classes = if request.path.start_with?(path)
      "text-lime-700 dark:text-[#6ACD12] font-medium"
    else
      "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
    end

    link_to name, path, class: classes
  end
end
