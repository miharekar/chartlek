require "test_helper"

class Overview::WordsTest < ActiveSupport::TestCase
  test "spells numbers without hyphens or and" do
    assert_equal "zero", Overview::Words.for(0)
    assert_equal "nineteen", Overview::Words.for(19)
    assert_equal "twenty", Overview::Words.for(20)
    assert_equal "sixty four", Overview::Words.for(64)
    assert_equal "one hundred", Overview::Words.for(100)
    assert_equal "four hundred sixty four", Overview::Words.for(464)
    assert_equal "one thousand", Overview::Words.for(1000)
    assert_equal "one thousand one", Overview::Words.for(1001)
    assert_equal "thirty three thousand four hundred sixty four", Overview::Words.for(33_464)
    assert_equal "two million three", Overview::Words.for(2_000_003)
  end
end
