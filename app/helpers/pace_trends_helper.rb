module PaceTrendsHelper
  FILTERS = [["Exclude pauses", "no_pauses"], ["Races only", "races"]].freeze
  PRESETS = [["3 mo", "3"], ["6 mo", "6"], ["1 yr", "12"], ["2 yr", "24"], ["All time", "all"]].freeze
  CARRIED_PARAMS = %w[no_pauses races from to distance].freeze

  def pace_trend_filter_chips
    safe_join(FILTERS.map { |label, key|
      active = params[key] == "1"
      toggle_button label, pressed: active, href: pace_trend_path(pace_trend_query.merge(key => (active ? nil : "1")).compact), data: {turbo_action: "replace", pace_trends_target: "link"}
    })
  end

  def pace_trend_presets
    button_group "Window" do
      safe_join(PRESETS.map { |label, key|
        segment label, data: {action: "pace-trends#preset", pace_trends_target: "preset", preset: key}
      })
    end
  end

  private
  def pace_trend_query
    request.query_parameters.slice(*CARRIED_PARAMS)
  end
end
