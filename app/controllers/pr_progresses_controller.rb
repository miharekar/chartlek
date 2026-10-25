class PrProgressesController < ApplicationController
  MODES = %w[progress beat magic].freeze

  def show
    options = params.permit(:mode, :days)
    @pr_progress = PrProgress.for_all
    @mode = options[:mode].presence_in(MODES) || "progress"
    @days = options[:days].to_i.then { PrProgress::REFERENCE_DAYS.include?(it) ? it : PrProgress::REFERENCE_DAYS.last }
  end
end
