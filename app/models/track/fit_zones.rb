class Track::FitZones
  TIME_IN_ZONE = 216
  SESSION = 18
  UNDEFINED_FLOOR = 255
  WANTED = {TIME_IN_ZONE => [0, 2, 6]}.freeze
  ARRAYS = {TIME_IN_ZONE => [2, 6]}.freeze

  def self.read(bytes)
    new(bytes).zones
  rescue Track::Error
    nil
  end

  def initialize(bytes)
    @bytes = bytes
  end

  def zones
    record = Track::FitFile.read(bytes, WANTED, ARRAYS)[TIME_IN_ZONE].find { it[0] == SESSION }
    floors = Array(record&.dig(6)).map { it || UNDEFINED_FLOOR }
    seconds = Array(record&.dig(2))

    {"floors" => floors.first(5), "max_hr" => floors.last, "seconds" => seconds[1, 5].map { (it / 1000.0).round }} if valid?(floors, seconds)
  end

  private
  attr_reader :bytes

  def valid?(floors, seconds)
    floors.size == 6 && floors.each_cons(2).all? { |low, high| low < high } && floors.first(5).none? { it.zero? || it == UNDEFINED_FLOOR } && seconds.size == 7 && seconds.all?
  end
end
