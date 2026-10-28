class Track::Reader
  def self.read(original)
    new(original).recording
  end

  def self.zones(original)
    new(original).zones
  end

  def initialize(original)
    @original = original
  end

  def recording
    name = @original.filename.to_s

    if name.end_with?(".json.gz")
      Track::Smashrun.parse(Zlib.gunzip(@original.download))
    elsif name.end_with?(".zip")
      read_zip
    else
      raise Track::Error, "Unsupported original: #{name}"
    end
  end

  def zones
    if @original.filename.to_s.end_with?(".zip")
      entry = zip_entry

      Track::FitZones.read(entry.get_input_stream.read) if File.extname(entry.name.to_s).casecmp?(".fit")
    end
  end

  private
  def zip_entry
    Zip::File.open_buffer(StringIO.new(@original.download)).entries.find(&:file?)
  end

  def read_zip
    entry = zip_entry

    case File.extname(entry.name.to_s).downcase
    when ".fit"
      Track::Fit.parse(entry.get_input_stream.read)
    when ".tcx"
      Track::Tcx.parse(entry.get_input_stream.read)
    else
      raise Track::Error, "Unsupported file in zip: #{entry.name}"
    end
  end
end
