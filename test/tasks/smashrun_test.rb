require "test_helper"
require "rake"

class SmashrunTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("smashrun:fetch")
    Rake::Task["smashrun:fetch"].reenable
  end

  test "aborts without Garmin runs" do
    with_env("SMASHRUN_USERNAME" => "runner@example.com", "SMASHRUN_PASSWORD" => "s3cret-pass") do
      error = assert_raises(SystemExit) { capture_io { Rake::Task["smashrun:fetch"].invoke } }
      assert_equal 1, error.status
    end
  end

  test "aborts without credentials" do
    create(:activity, source: "garmin")

    with_env("SMASHRUN_USERNAME" => nil, "SMASHRUN_PASSWORD" => nil) do
      _, err = capture_io do
        assert_raises(SystemExit) { Rake::Task["smashrun:fetch"].invoke }
      end
      assert_includes err, "SMASHRUN_USERNAME"
    end
  end

  private
  def with_env(values)
    previous = values.keys.index_with { ENV[it] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
