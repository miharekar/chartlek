require "test_helper"

class Track::FitFileTest < ActiveSupport::TestCase
  WANTED = {20 => [253, 0, 5, 4], 21 => [0, 1]}.freeze

  def record(timestamp, **fields)
    [20, {253 => [FitBuilder::UINT32, timestamp]}.merge(fields)]
  end

  def read(bytes, wanted = WANTED)
    Track::FitFile.read(bytes, wanted)
  end

  test "reads the wanted fields of the wanted messages in file order" do
    bytes = FitBuilder.bytes([record(10, 5 => [FitBuilder::UINT32, 500], 3 => [FitBuilder::UINT8, 140]), [21, {0 => [FitBuilder::ENUM, 0]}], record(11, 4 => [FitBuilder::UINT8, 80])])

    assert_equal [{253 => 10, 5 => 500}, {253 => 11, 4 => 80}], read(bytes)[20]
    assert_equal [{0 => 0}], read(bytes)[21]
  end

  test "reads big-endian definitions" do
    bytes = FitBuilder.bytes([record(0x01020304, 0 => [FitBuilder::SINT32, -5], 4 => [FitBuilder::UINT16, 0x0102])], big: true)

    assert_equal [{253 => 0x01020304, 0 => -5, 4 => 0x0102}], read(bytes)[20]
  end

  test "skips developer fields" do
    bytes = FitBuilder.bytes([[20, {253 => [FitBuilder::UINT32, 7]}, {developer: 3}], record(8)])

    assert_equal [7, 8], read(bytes)[20].pluck(253)
  end

  test "turns invalid values into nil, also inside arrays" do
    bytes = FitBuilder.bytes([[20, {253 => [FitBuilder::UINT32, 0xFFFFFFFF], 0 => [FitBuilder::SINT32, 0x7FFFFFFF], 5 => [FitBuilder::UINT32, [1, 0xFFFFFFFF, 3]], 4 => [FitBuilder::UINT8, 0xFF]}]])

    assert_equal [{253 => nil, 0 => nil, 5 => [1, nil, 3], 4 => nil}], Track::FitFile.read(bytes, WANTED, {20 => [5]})[20]
  end

  test "reads an unexpected array as nil and a declared array as an array" do
    bytes = FitBuilder.bytes([[20, {253 => [FitBuilder::UINT32, [7, 8]], 5 => [FitBuilder::UINT32, [1, 2]], 4 => [FitBuilder::UINT8, 3]}]])

    assert_equal [{253 => nil, 5 => nil, 4 => 3}], read(bytes)[20]
    assert_equal [{253 => nil, 5 => [1, 2], 4 => 3}], Track::FitFile.read(bytes, WANTED, {20 => [5]})[20]
  end

  test "reads a string field as nil" do
    bytes = FitBuilder.bytes([[20, {253 => [FitBuilder::UINT32, 7], 5 => [FitBuilder::STRING, "abc"]}]])

    assert_equal [{253 => 7, 5 => nil}], read(bytes)[20]
  end

  test "uses the latest definition of a redefined local type" do
    bytes = FitBuilder.bytes([record(1, 4 => [FitBuilder::UINT8, 9]), record(2)])

    assert_equal [{253 => 1, 4 => 9}, {253 => 2}], read(bytes)[20]
  end

  test "keeps local types apart" do
    bytes = FitBuilder.bytes([record(1), [20, {253 => [FitBuilder::UINT32, 2], 4 => [FitBuilder::UINT8, 6]}, {local: 1}], record(3)])

    assert_equal [1, 2, 3], read(bytes)[20].pluck(253)
  end

  test "skips messages that were not asked for" do
    bytes = FitBuilder.bytes([[999, {1 => [FitBuilder::UINT32, 5]}], record(4)])

    assert_equal({20 => [{253 => 4}], 21 => []}, read(bytes))
  end

  test "frames a compressed timestamp header but derives no timestamp" do
    body = FitBuilder.bytes([[20, {5 => [FitBuilder::UINT32, 1]}]])[14...-2] + [0x80, 99].pack("CL<")

    assert_equal [{5 => 1}, {5 => 99}], read(FitBuilder.wrap(body))[20]
  end

  test "reads a 12-byte header" do
    assert_equal [5], read(FitBuilder.bytes([record(5)], header: 12))[20].pluck(253)
  end

  test "rejects a file that is not FIT" do
    ["", "not a fit file", "x" * 40, "\x0E\x20\x00\x00\x00\x00\x00\x00NOPE\x00\x00".b].each do |bytes|
      assert_raises(Track::Error) { read(bytes) }
    end
  end

  test "rejects a data message for an undefined local type" do
    assert_raises(Track::Error) { read(FitBuilder.wrap([0x03, 1, 2, 3].pack("C*"), header: 12)) }
  end

  test "raises Track::Error for every truncation of a valid file" do
    whole = FitBuilder.bytes([record(1, 5 => [FitBuilder::UINT32, 100]), [21, {0 => [FitBuilder::ENUM, 0]}], [20, {253 => [FitBuilder::UINT32, 2]}, {developer: 2}]])

    (0...whole.bytesize - 2).each do |cut|
      assert_raises(Track::Error, "cut at #{cut}") { read(whole.byteslice(0, cut)) }
    end
  end

  test "raises Track::Error or parses every cut of the data section, reaching each inner check" do
    body = FitBuilder.message(20, {253 => [FitBuilder::UINT32, 1], 5 => [FitBuilder::UINT32, 100]}) + FitBuilder.message(21, {0 => [FitBuilder::ENUM, 0]}) + FitBuilder.message(20, {253 => [FitBuilder::UINT32, 2]}, {developer: 2})
    messages = []

    (0..body.bytesize).each do |cut|
      read(FitBuilder.wrap(body.byteslice(0, cut)))
    rescue Track::Error => error
      messages << error.message
    end

    assert_includes messages, "Unreadable FIT file: definition runs past the end"
    assert_includes messages, "Unreadable FIT file: message runs past the end"
  end

  test "rejects a definition cut inside its header, before the developer count and inside the developer table" do
    definition = FitBuilder.message(20, {253 => [FitBuilder::UINT32, 1]}, {developer: 2}).byteslice(0, 1 + 5 + 3 + 1 + 3)

    [1, 3, 9, 10].each do |cut|
      error = assert_raises(Track::Error, "cut at #{cut}") { read(FitBuilder.wrap(definition.byteslice(0, cut))) }
      assert_equal "Unreadable FIT file: definition runs past the end", error.message
    end
  end
end
