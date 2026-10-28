class Track::Fit
  EPOCH = 631_065_600
  RECORD = 20
  LAP = 19
  EVENT = 21
  WANTED = {RECORD => [253, 0, 1, 2, 3, 4, 5, 53, 78], LAP => [2, 23], EVENT => [0, 1, 253]}.freeze
  TIMER = 0
  START = 0
  STOP_ALL = 4

  def self.parse(bytes)
    new(Track::FitFile.read(bytes, WANTED)).recording
  end

  def initialize(messages)
    @messages = messages
  end

  def recording
    records = @messages[RECORD]
    raise Track::Error, "FIT file has no records" if records.empty?
    raise Track::Error, "FIT record has no timestamp" if records.any? { it[253].nil? }

    first = records.first[253]
    pauses = self.pauses

    Track::Recording.new(records.map { row(it, first, pauses) }, laps:)
  end

  private
  def laps
    @messages[LAP].select { it[2] }.map { {at: at(it[2]), intensity: it[23]} }
  end

  def row(record, first, pauses)
    timestamp = record[253]
    paused = pauses.sum { |from, to| (to <= timestamp) ? to - from : 0 }

    {
      at: at(timestamp),
      t: (timestamp - first - paused).to_f,
      d: scaled(record[5], 100.0),
      lat: coordinate(record[0]),
      lng: coordinate(record[1]),
      alt: altitude(record[2] || record[78]),
      hr: record[3],
      cad: cadence(record[4], record[53])
    }
  end

  def at(timestamp)
    (timestamp + EPOCH).to_f
  end

  def scaled(raw, scale)
    raw / scale if raw
  end

  def coordinate(raw)
    raw * (180.0 / 2**31) if raw
  end

  def altitude(raw)
    raw / 5.0 - 500 if raw
  end

  def cadence(cadence, fraction)
    if cadence && fraction
      (cadence + fraction / 128.0) * 2
    elsif cadence
      cadence * 2
    end
  end

  def pauses
    stopped = nil

    @messages[EVENT].select { it[0] == TIMER && it[253] }.each_with_object([]) do |event, pauses|
      if event[1] == STOP_ALL
        stopped ||= event[253]
      elsif event[1] == START && stopped
        pauses << [stopped, event[253]]
        stopped = nil
      end
    end
  end
end
