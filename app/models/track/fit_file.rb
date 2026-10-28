class Track::FitFile
  BASE_TYPES = {
    0 => ["C", 1, 0xFF],
    1 => ["c", 1, 0x7F],
    2 => ["C", 1, 0xFF],
    3 => ["s", 2, 0x7FFF],
    4 => ["S", 2, 0xFFFF],
    5 => ["l", 4, 0x7FFFFFFF],
    6 => ["L", 4, 0xFFFFFFFF],
    10 => ["C", 1, 0],
    11 => ["S", 2, 0],
    12 => ["L", 4, 0],
    13 => ["C", 1, 0xFF],
    14 => ["q", 8, 0x7FFFFFFFFFFFFFFF],
    15 => ["Q", 8, 0xFFFFFFFFFFFFFFFF],
    16 => ["Q", 8, 0]
  }.freeze

  def self.read(bytes, wanted, arrays = {})
    new(bytes.b, wanted, arrays).read
  end

  def initialize(bytes, wanted, arrays)
    @bytes = bytes
    @wanted = wanted
    @arrays = arrays
  end

  def read
    position, last = bounds
    definitions = {}
    messages = wanted.transform_values { [] }

    while position < last
      header = bytes.getbyte(position)
      position += 1

      if header & 0x80 == 0 && header & 0x40 != 0
        definition, position = definition_at(position, header, last)
        definitions[header & 0xF] = definition
      else
        local = (header & 0x80 != 0) ? (header >> 5) & 3 : header & 0xF
        definition = definitions[local]
        check(definition, "data message for undefined local type #{local}")
        check(position + definition[:size] <= last, "message runs past the end")

        messages[definition[:global]] << message(definition, position) if definition[:fields]
        position += definition[:size]
      end
    end

    messages
  end

  private
  attr_reader :bytes, :wanted, :arrays

  def bounds
    check(bytes.bytesize >= 12 && [12, 14].include?(bytes.getbyte(0)) && bytes[8, 4] == ".FIT", "not a FIT file")
    first = bytes.getbyte(0)
    last = first + bytes.unpack1("V", offset: 4)
    check(last <= bytes.bytesize, "data runs past the end")

    [first, last]
  end

  def definition_at(position, header, last)
    check(position + 5 <= last, "definition runs past the end")
    big = bytes.getbyte(position + 1) == 1
    global = bytes.unpack1(big ? "n" : "v", offset: position + 2)
    count = bytes.getbyte(position + 4)
    position += 5
    triples, position = triples_at(position, count, last)
    skipped = 0

    if header & 0x20 != 0
      check(position + 1 <= last, "definition runs past the end")
      developer, position = triples_at(position + 1, bytes.getbyte(position), last)
      skipped = developer.sum { it[1] }
    end

    [layout(global, triples, big, skipped), position]
  end

  def triples_at(position, count, last)
    check(position + count * 3 <= last, "definition runs past the end")

    [bytes.byteslice(position, count * 3).bytes.each_slice(3).to_a, position + count * 3]
  end

  def layout(global, triples, big, skipped)
    size = triples.sum { it[1] } + skipped
    numbers = wanted[global]

    if numbers
      format = +""
      fields = []

      triples.each do |number, width, type|
        if numbers.include?(number)
          array = arrays.fetch(global, []).include?(number)
          format << directive(width, type, big, array)
          fields << field(number, width, type, array)
        else
          format << "x#{width}"
        end
      end

      {global:, size:, format:, fields:}
    else
      {global:, size:}
    end
  end

  def directive(width, type, big, array)
    letter, unit, = BASE_TYPES[type & 0x1F]

    if supported?(width, unit, array)
      letter += (big ? ">" : "<") if unit > 1
      (width == unit) ? letter : "#{letter}#{width / unit}"
    else
      "x#{width}"
    end
  end

  def field(number, width, type, array)
    _, unit, invalid = BASE_TYPES[type & 0x1F]

    if supported?(width, unit, array)
      [number, array ? width / unit : nil, invalid]
    else
      [number, 0, nil]
    end
  end

  def supported?(width, unit, array)
    unit && width.positive? && (width % unit).zero? && (array || width == unit)
  end

  def message(definition, position)
    values = bytes.unpack(definition[:format], offset: position)

    definition[:fields].to_h do |number, count, invalid|
      if count == 0
        [number, nil]
      elsif count
        [number, values.shift(count).map { it unless it == invalid }]
      else
        value = values.shift
        [number, (value unless value == invalid)]
      end
    end
  end

  def check(condition, reason)
    raise Track::Error, "Unreadable FIT file: #{reason}" unless condition
  end
end
