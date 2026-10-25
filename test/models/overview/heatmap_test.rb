require "test_helper"

class Overview::HeatmapTest < ActiveSupport::TestCase
  TODAY = Date.new(2024, 3, 20)

  def run_on(time, km)
    build(:activity, local_started_at: Time.utc(*time), started_at: Time.utc(*time), distance_m: km * 1000, timer_s: km * 300)
  end

  def heatmap(runs, **options)
    Overview.new(runs, today: TODAY, **options).heatmap
  end

  test "level counts thresholds below the distance" do
    assert_equal 0, Overview::Heatmap.level(1, Overview::Heatmap::WEEKLY_THRESHOLDS)
    assert_equal 1, Overview::Heatmap.level(1.1, Overview::Heatmap::WEEKLY_THRESHOLDS)
    assert_equal 3, Overview::Heatmap.level(50, Overview::Heatmap::WEEKLY_THRESHOLDS)
    assert_equal 5, Overview::Heatmap.level(60.1, Overview::Heatmap::WEEKLY_THRESHOLDS)
    assert_equal 6, Overview::Heatmap.level(81, Overview::Heatmap::WEEKLY_THRESHOLDS)
  end

  test "all time has years as rows and monday weeks summed across days" do
    data = heatmap([run_on([2023, 12, 20, 7], 25), run_on([2023, 12, 22, 7], 30), run_on([2024, 3, 5, 7], 5)])
    cell = data[:cells].find { it[:tip].first == "Week of 18 Dec 2023" }

    assert_equal %w[2023 2024], data[:rows]
    assert_equal 53, data[:cols]
    assert_equal 0, cell[:row]
    assert_equal 50, cell[:col]
    assert_equal 4, cell[:level]
    assert_equal "55.0 km", cell[:tip].last
    assert_equal "/overview/2023/12", cell[:href]
    assert_equal 0, data[:cells].find { it[:tip].first == "Week of 1 Jan 2024" }[:level]
  end

  test "weeks without runs are level zero and have no link" do
    data = heatmap([run_on([2024, 1, 3, 7], 10), run_on([2024, 3, 5, 7], 5)])
    empty = data[:cells].find { it[:tip].first == "Week of 15 Jan 2024" }

    assert_equal 0, empty[:level]
    assert_nil empty[:href]
  end

  test "alternate scale uses quantiles of weeks that have runs" do
    km = [10, 20, 30, 40, 50]
    runs = km.each_with_index.map { |distance, index| run_on([2024, 1, 1 + index * 7, 7], distance) }
    data = heatmap(runs)

    assert_equal [0, 20.0, 30.0, 40.0, 46.0, 48.8], data[:alt_thresholds]
    levels = data[:cells].select { it[:level] > 0 }.sort_by { it[:tip].last.to_f }.pluck(:alt)
    assert_equal [1, 1, 2, 3, 6], levels
  end

  test "year view is a day calendar" do
    data = heatmap([run_on([2024, 1, 2, 7], 12)], year: 2024)
    day = data[:cells].find { it[:tip].first == "2 Jan 2024" }

    assert_equal %w[Mon Tue Wed Thu Fri Sat Sun], data[:rows]
    assert_equal 1, day[:row]
    assert_equal 0, day[:col]
    assert_equal 3, day[:level]
    assert_equal "12.0 km", day[:tip].last
    assert day[:external]
    assert_equal 80, data[:cells].size
    assert_equal "No run", data[:cells].first[:tip].last
    assert_equal "Jan", data[:columns].first[:label]
    assert_equal %w[Jan Feb Mar], data[:columns].pluck(:label)
    assert_nil day[:alt]
  end

  test "month view numbers the days" do
    data = heatmap([run_on([2024, 2, 14, 7], 6)], year: 2024, month: 2)

    assert_equal 29, data[:cells].size
    assert_equal "14", data[:cells].find { it[:tip].first == "14 Feb 2024" }[:text]
    assert_equal [{label: "Feb", col: 0}], data[:columns]
    assert_equal 5, data[:cols]
  end
end
