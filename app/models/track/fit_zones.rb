class Track::FitZones
  TIME_IN_ZONE = 216
  SESSION = 18
  FIELDS = {0 => :type, 2 => :seconds, 6 => :floors}.freeze
  WIDTHS = {2 => 1, 4 => 2, 6 => 4}.freeze
  UNPACK = {1 => %w[C C], 2 => %w[v n], 4 => %w[V N]}.freeze
  UNDEFINED_SECONDS = 0xFFFFFFFF

  def self.read(bytes)
    new(bytes.b).zones
  end

  def initialize(bytes)
    @bytes = bytes
  end

  def zones
    record = session_record
    floors = record&.dig(:floors)
    seconds = record&.dig(:seconds)

    {"floors" => floors.first(5), "max_hr" => floors.last, "seconds" => seconds[1, 5].map { (it / 1000.0).round }} if valid?(floors, seconds)
  end

  private
  attr_reader :bytes

  def valid?(floors, seconds)
    floors&.size == 6 && floors.each_cons(2).all? { |low, high| low < high } && floors.first(5).none? { it.zero? || it == 255 } && seconds&.size == 7 && seconds.none? { it == UNDEFINED_SECONDS }
  end

  def session_record
    position = bytes.getbyte(0).to_i
    last = [position + bytes[4, 4].to_s.unpack1("V").to_i, bytes.bytesize].min
    definitions = {}
    found = nil

    if bytes[8, 4] == ".FIT"
      while position < last && !found
        header = bytes.getbyte(position)
        position += 1

        if header & 0x80 != 0
          position += definitions.dig((header >> 5) & 3, :size).to_i
        elsif header & 0x40 != 0
          read = definition_at(position, header)
          break unless read

          definition, position = read
          definitions[header & 0xf] = definition
        else
          definition = definitions[header & 0xf]
          break unless definition && position + definition[:size] <= bytes.bytesize

          record = data_at(position, definition) if definition[:message] == TIME_IN_ZONE
          found = record if record && record[:type] == SESSION
          position += definition[:size]
        end
      end
    end

    found
  end

  def definition_at(position, header)
    head = take(position, 5)
    count = head&.getbyte(4)
    table = take(position + 5, count * 3) if count
    return unless table

    big = head.getbyte(1) == 1
    message = head[2, 2].unpack1(big ? "n" : "v")
    fields = table.bytes.each_slice(3).to_a
    size = fields.sum { it[1] }
    position += 5 + count * 3

    if header & 0x20 != 0
      developer = take(position, 1)&.getbyte(0)
      table = take(position + 1, developer * 3) if developer
      return unless table

      size += table.bytes.each_slice(3).sum { it[1] }
      position += 1 + developer * 3
    end

    [{message:, big:, fields:, size:}, position]
  end

  def take(position, length)
    slice = bytes.byteslice(position, length)
    slice if slice&.bytesize == length
  end

  def data_at(position, definition)
    definition[:fields].each_with_object({}) do |(number, size, type), record|
      name = FIELDS[number]
      width = WIDTHS[type & 0x1f]

      if name && width && size % width == 0
        format = UNPACK.fetch(width)[definition[:big] ? 1 : 0]
        values = bytes[position, size].unpack(format * (size / width))
        record[name] = (name == :type) ? values.first : values
      end

      position += size
    end
  end
end
