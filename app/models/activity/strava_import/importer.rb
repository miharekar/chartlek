class Activity::StravaImport::Importer
  MINIMUM_DISTANCE_M = 100
  GARMIN_MARGIN = 10.minutes

  attr_reader :report

  def initialize(source)
    @source = source
    @report = Activity::StravaImport::Report.new
  end

  def import
    first_garmin = Activity.where(source: "garmin").minimum(:started_at)
    @garmin_since = first_garmin - GARMIN_MARGIN if first_garmin
    @source.rows.each { import_row(it) }
    report
  end

  private
  def import_row(row)
    if @source.run?(row)
      import_run(@source.attributes_for(row))
    else
      report.increment(:non_run)
    end
  end

  def import_run(attributes)
    if attributes[:external_id].nil? || attributes[:started_at].nil? || attributes[:timer_s].nil? || attributes[:distance_m].nil?
      report.increment(:invalid)
    elsif attributes[:distance_m] < MINIMUM_DISTANCE_M
      report.increment(:too_short)
    elsif @garmin_since && attributes[:started_at] >= @garmin_since
      report.increment(:garmin_era)
    elsif Activity.exists?(source: "strava", external_id: attributes[:external_id])
      report.increment(:already_imported)
    else
      save(attributes)
    end
  end

  def save(attributes)
    if Activity.new(attributes).save
      report.increment(:imported)
    else
      report.increment(:invalid)
    end
  end
end
