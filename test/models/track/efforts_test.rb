require "test_helper"

class Track::EffortsTest < ActiveSupport::TestCase
  def efforts(t, d)
    Track::Efforts.new("t" => t, "d" => d).all
  end

  test "lists only the distances the run covers" do
    assert_equal ["250 m", "400 m", "1 km"], efforts([0, 300, 600], [0, 1000, 2000]).pluck(:label)
    assert_empty efforts([0, 60], [0, 200])
  end

  test "finds the fastest window and interpolates between samples" do
    result = efforts([0, 100, 150, 350], [0, 500, 1000, 1500]).find { it[:label] == "400 m" }

    assert result[:from].between?(500.0, 600.0)
    assert_in_delta result[:from] + 400, result[:to]
    assert_in_delta 40.0, result[:time]
    assert_in_delta 100.0, result[:pace]
  end

  test "a window that ends on a sample while starting between samples wins" do
    result = efforts([0, 500, 520, 1520], [0, 500, 600, 1100]).find { it[:label] == "250 m" }

    assert_in_delta 350.0, result[:from]
    assert_in_delta 600.0, result[:to]
    assert_in_delta 170.0, result[:time]
  end

  test "gives a vdot from 400 m up and none below" do
    result = efforts([0, 300, 600, 900], [0, 500, 1000, 1500])

    assert_nil result.first[:vdot]
    assert_predicate result.second[:vdot], :positive?
  end

  test "track exposes its efforts" do
    track = Track.new(data: {"t" => [0, 300, 600], "d" => [0, 1000, 2000]})

    assert_equal 3, track.efforts.size
  end
end
