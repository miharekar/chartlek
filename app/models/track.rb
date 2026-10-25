class Track < ApplicationRecord
  class Error < StandardError; end

  BAR_M = 100.0

  belongs_to :activity

  def bars(size = BAR_M)
    Metrics.new(Recording.new(rows)).splits(size)
  end

  private
  def rows
    keys = data.keys.map(&:to_sym)
    data.values.transpose.map { keys.zip(it).to_h }
  end
end
