module TrainingBandsHelper
  CATEGORY_LABELS = {"pace" => "Pace", "hr" => "Heart rate", "grade" => "Grade"}.freeze
  VIEW_LABELS = {"absolute" => "Absolute", "percent" => "%"}.freeze
  SWATCH = "mr-1.5 inline-block size-2.5 rounded-sm"

  def training_bands_info
    paces = TrainingBands::PACE_GROUPS.map { |label, zones| "#{label} #{training_bands_pace_range(zones)}" }.join(", ")

    "Training time per week, stacked by band, so the colours show how your running splits between easy and hard. Pace uses the 37 pace zones, grouped as #{paces}. Heart rate is time in your five zones. Grade is the slope over each stretch of about 100 m. Absolute shows hours per week; % shows each band's share of that week's running, so hiding bands shows how much of your running they are. Heart rate zones are today's, so older weeks are counted with today's boundaries. Drag the timeline to change the window, and hover the chart for a week."
  end

  def training_bands_categories(bands)
    button_group "Category" do
      safe_join(bands.categories.map { |name|
        segment CATEGORY_LABELS.fetch(name), selected: name == bands.category, data: {action: "training-bands#changeCategory", training_bands_target: "category", value: name}
      })
    end
  end

  def training_bands_views(bands)
    button_group "View" do
      safe_join(VIEW_LABELS.map { |name, label|
        segment label, selected: name == bands.view, data: {action: "training-bands#changeView", training_bands_target: "view", value: name}
      })
    end
  end

  def training_bands_presets
    button_group "Window" do
      safe_join(PaceTrendsHelper::PRESETS.map { |label, key|
        segment label, data: {action: "training-bands#preset", training_bands_target: "preset", preset: key}
      })
    end
  end

  def training_bands_filters(bands)
    safe_join(bands.categories.map { |name|
      tag.div class: "flex flex-wrap items-center gap-2", hidden: name != bands.category, role: "group", aria: {label: "#{CATEGORY_LABELS.fetch(name)} bands"}, data: {training_bands_target: "filters", category: name} do
        safe_join(bands.groups(name).each_with_index.map { |group, index|
          colors = group[:bands].map { TrainingBands::COLORS.fetch(name).fetch(it) }
          swatch = tag.span(class: SWATCH, style: "background: linear-gradient(90deg, #{(colors * 2).first(colors.size.clamp(2, 99)).join(", ")})")
          toggle_button safe_join([swatch, group[:label]]), pressed: true, data: {action: "training-bands#toggle", group: index}
        })
      end
    })
  end

  private
  def training_bands_pace_range(zones)
    if zones.first.zero?
      "under #{PaceZones::WALK_BELOW_KMH} km/h"
    elsif zones.last == PaceZones::ZOOM
      "faster than #{PaceZones.label(zones.first - 1)} /km"
    elsif zones.first == 1
      "slower than #{PaceZones.label(zones.last)} /km"
    else
      "#{PaceZones.label(zones.first - 1)} to #{PaceZones.label(zones.last)} /km"
    end
  end
end
