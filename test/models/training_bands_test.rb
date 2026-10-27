require "test_helper"

class TrainingBandsTest < ActiveSupport::TestCase
  test "has no data and only the default category without runs" do
    bands = TrainingBands.new(category: "hr")

    assert_not bands.data?
    assert_equal %w[pace], bands.categories
    assert_equal "pace", bands.category
  end
end
