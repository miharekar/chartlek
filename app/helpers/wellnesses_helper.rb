module WellnessesHelper
  CHARTS = {
    rhr: ["Resting heart rate", "One dot per day, with the mean of the values in the 7 days ending on it as the line, when that window holds at least 4 values. A day without a reading has no point on the line."],
    hrv: ["Heart rate variability", "Last night's average per night, over Garmin's baseline band. The dot colour is Garmin's status for that night: balanced, unbalanced, low or poor."],
    sleep: ["Sleep", "Nightly sleep in hours, stacked by stage: deep, light and REM, so the bar is the time asleep; the awake time is in the tooltip. Before Garmin recorded stages the bar is the total sleep time. The line is Garmin's sleep score on the right axis, from about 2021. A night belongs to the day you woke up."],
    bb: ["Body Battery", "Each bar runs from the day's lowest to its highest Body Battery. The mark is the value at wake."],
    stress: ["Stress", "Garmin's average stress level per day."],
    weight: ["Weight", "One dot per day with a weigh-in. The line is a 30-day centred moving average."],
    vdot: ["Top-run VDOT", "The VDOT of your top runs, the line Pace Trends fits its trend to. Garmin's Personal API has no VO2max."],
    zones: ["Time in heart rate zones per week", "Weekly time in each zone, from the run summaries. Zone ranges are today's, Garmin timed each run with the zones in force then."]
  }.freeze

  def wellness_presets
    button_group "Window" do
      safe_join(PaceTrendsHelper::PRESETS.map { |label, key|
        segment label, data: {action: "wellness#preset", wellness_target: "preset", preset: key}
      })
    end
  end
end
