module Activity::SmashrunImport
  extend ActiveSupport::Concern

  class_methods do
    def import_smashrun(client, io: $stdout)
      Activity::SmashrunImport::Importer.new(client, io:).import
    end
  end
end
