require "test_helper"

class FoodTest < ActiveSupport::TestCase
  test "picks the item and multiple closest to the calories" do
    assert_equal "3 bananas", Food.for(315).to_s
    assert_equal "1 kremšnita", Food.for(450).to_s
    assert_equal "1 pizza", Food.for(1600).to_s
  end

  test "multiples stay between 1 and 12" do
    assert_operator Food.for(100_000).count, :<=, Food::MAX_COUNT
    assert_equal 1, Food.for(1).count
  end

  test "is nil without calories" do
    assert_nil Food.for(nil)
    assert_nil Food.for(0)
  end
end
