class PrProgress::Magic
  STEPS = [[5000, 60], [21097.5, 300], [Float::INFINITY, 900]].freeze
  LIMIT = 3

  Target = Data.define(:name, :distance_m, :pr_s, :target_s, :gap_s, :percent)

  def self.for(records)
    records.filter_map { target_for(it) }.sort_by.with_index { |target, index| [target.percent, index] }.first(LIMIT)
  end

  def self.target_for(record)
    step = STEPS.find { |up_to, _| record.distance_m <= up_to }.last
    target_s = (record.time_s.fdiv(step).ceil - 1) * step

    if target_s > 0
      gap_s = record.time_s - target_s
      Target.new(name: record.name, distance_m: record.distance_m, pr_s: record.time_s, target_s:, gap_s:, percent: gap_s.fdiv(record.time_s) * 100)
    end
  end
end
