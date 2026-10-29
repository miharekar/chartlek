module ApplicationHelper
  THEME_ICONS = {
    "system" => '<rect x="2" y="3" width="12" height="8.5" rx="1.5"/><path d="M5.5 14h5M8 11.5V14"/>'.html_safe,
    "light" => '<circle cx="8" cy="8" r="2.75"/><path d="M8 1.5v1.5M8 13v1.5M1.5 8H3M13 8h1.5M3.4 3.4l1 1M11.6 11.6l1 1M3.4 12.6l1-1M11.6 4.4l1-1"/>'.html_safe,
    "dark" => '<path d="M13.5 9.5A5.75 5.75 0 0 1 6.5 2.5a5.75 5.75 0 1 0 7 7Z"/>'.html_safe
  }.freeze
  GITHUB_ICON = "M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656".freeze
  IDLE_NAV = "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100".freeze

  def theme_switch
    button_group "Theme" do
      safe_join(ThemesController::THEMES.map { |theme|
        button_to theme_path, method: :patch, params: {theme:}, form: {class: "contents", data: {turbo: false}}, title: theme.capitalize, aria: {label: theme.capitalize, pressed: current_theme == theme}, class: ControlsHelper::ICON_SEGMENT do
          tag.svg(THEME_ICONS.fetch(theme), viewBox: "0 0 16 16", class: "size-4", fill: "none", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round", aria: {hidden: true})
        end
      })
    end
  end

  def github_link
    label = "Chartlek on GitHub"
    link_to "https://github.com/miharekar/chartlek", title: label, aria: {label:}, target: "_blank", rel: "noopener", class: "inline-flex min-h-8 items-center #{IDLE_NAV}" do
      tag.svg(tag.path(d: GITHUB_ICON), viewBox: "0 0 16 16", class: "size-4", fill: "currentColor", aria: {hidden: true})
    end
  end

  def nav_link_to(name, path, match: [path])
    current = match.any? { |prefix| request.path.start_with?(prefix) }
    classes = current ? "#{WidgetsHelper::ACCENT} font-medium" : IDLE_NAV

    link_to name, path, class: classes, aria: {current: ("page" if current)}
  end
end
