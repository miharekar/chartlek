class Track::Reader
  def self.read(original)
    new(original).recording
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

  private
  def read_zip
    entry = Zip::File.open_buffer(StringIO.new(@original.download)).entries.find(&:file?)

    case File.extname(entry.name.to_s).downcase
    when ".fit"
      Tempfile.create(["track", ".fit"], binmode: true) do |file|
        file.write(entry.get_input_stream.read)
        file.flush
        Track::Fit.parse(file.path)
      end
    when ".tcx"
      Track::Tcx.parse(entry.get_input_stream.read)
    else
      raise Track::Error, "Unsupported file in zip: #{entry.name}"
    end
  end
end
