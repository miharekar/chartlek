require "test_helper"

class WellnessDayTest < ActiveSupport::TestCase
  test "the log shows no wellness values" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    original = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = logger
    logger.level = Logger::DEBUG

    WellnessDay.create!(date: Date.new(2026, 10, 27), resting_hr: 4242, hrv_status: "SENTINELSTATUS", weight_kg: 77.7777, raw: {"summary" => {"restingHeartRate" => 4242}})
    WellnessDay.find_by!(date: Date.new(2026, 10, 27)).update!(stress_avg: 4343)

    assert_includes io.string, "[FILTERED]"
    assert_no_match(/4242|4343|SENTINELSTATUS|77\.7777/, io.string)
  ensure
    ActiveRecord::Base.logger = original
  end
end
