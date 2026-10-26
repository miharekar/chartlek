require "test_helper"

class Overview::ScatterTest < ActiveSupport::TestCase
  def run_with(km, timer_s, **attrs)
    create(:activity, distance_m: km * 1000, timer_s:, **attrs)
  end

  test "each average takes its km over the runs that have the metric" do
    runs = [
      run_with(10, 3000, avg_hr: 150),
      run_with(20, 6000, avg_hr: nil),
      run_with(30, 9000, avg_hr: 130)
    ]

    average = Overview::Scatter.new(runs).data[:average]

    assert_equal({km: 20.0, value: 300.0}, average[:pace])
    assert_equal({km: 20.0, value: 140.0}, average[:hr])
  end

  test "an average over a subset uses only that subset's km" do
    runs = [run_with(5, 1500, avg_hr: 150), run_with(25, 7500, avg_hr: nil), run_with(45, 13_500, avg_hr: nil)]

    average = Overview::Scatter.new(runs).data[:average]

    assert_equal 25.0, average[:pace][:km]
    assert_equal({km: 5.0, value: 150.0}, average[:hr])
  end

  test "a metric nobody has is absent" do
    runs = [run_with(5, 1500, avg_hr: nil)]

    assert_nil Overview::Scatter.new(runs).data[:average][:hr]
  end

  test "a selection of every run lands where the average does" do
    runs = [run_with(10, 3000, avg_hr: 150), run_with(20, 6000, avg_hr: nil), run_with(30, 9000, avg_hr: 130)]
    data = Overview::Scatter.new(runs).data
    rows = data[:runs]
    with_hr = rows.select { it[:hr] }

    assert_in_delta data[:average][:hr][:km], with_hr.sum { it[:km] } / with_hr.size, 0.01
    assert_in_delta data[:average][:hr][:value], with_hr.sum { it[:hr] }.to_f / with_hr.size, 0.1
    assert_in_delta data[:average][:pace][:km], rows.sum { it[:km] } / rows.size, 0.01
  end
end
