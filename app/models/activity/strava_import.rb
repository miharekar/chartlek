module Activity::StravaImport
  extend ActiveSupport::Concern

  class_methods do
    def import_strava(path)
      Activity::StravaImport::Importer.new(Activity::StravaImport::Archive.new(File.join(path, "activities.csv"))).import
    end

    def import_strava_activities(summaries)
      Activity::StravaImport::Importer.new(Activity::StravaImport::Api.new(summaries)).import
    end
  end
end
