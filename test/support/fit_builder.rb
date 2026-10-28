module FitBuilder
  TYPES = {0 => ["C", 1], 1 => ["c", 1], 2 => ["C", 1], 3 => ["s", 2], 4 => ["S", 2], 5 => ["l", 4], 6 => ["L", 4], 7 => ["a", 1], 10 => ["C", 1], 11 => ["S", 2], 12 => ["L", 4], 13 => ["C", 1], 14 => ["q", 8], 15 => ["Q", 8], 16 => ["Q", 8]}.freeze
  ENUM = 0
  SINT8 = 1
  UINT8 = 2
  UINT16 = 4
  SINT32 = 5
  UINT32 = 6
  STRING = 7
  BYTE = 13

  module_function

  def bytes(messages, big: false, header: 14)
    wrap(messages.map { message(*it, big:) }.join.b, header:)
  end

  def wrap(body, header: 14)
    head = [header, 0x20, 0, body.bytesize].pack("CCvV") + ".FIT"
    head += [0].pack("v") if header == 14

    head.b + body + [0].pack("v")
  end

  def message(global, fields, options = {}, big: false)
    local = options.fetch(:local, 0)
    developer = options.fetch(:developer, 0)
    triples = fields.map { |number, (type, value)| [number, size(type, value), type] }
    definition = [0x40 | local | (developer.positive? ? 0x20 : 0), 0, big ? 1 : 0].pack("C3") + [global].pack(big ? "n" : "v") + [fields.size].pack("C") + triples.flatten.pack("C*")
    definition += [1, 0, developer, 0].pack("C4") if developer.positive?
    data = fields.map { |_, (type, value)| pack(type, value, big) }.join + "\xAA".b * developer

    definition.b + [local].pack("C") + data.b
  end

  def size(type, value)
    value.is_a?(String) ? value.bytesize : TYPES.fetch(type)[1] * Array(value).size
  end

  def pack(type, value, big)
    return value.b if value.is_a?(String)

    letter, width = TYPES.fetch(type)
    letter += (big ? ">" : "<") if width > 1

    Array(value).pack(letter * Array(value).size)
  end
end
