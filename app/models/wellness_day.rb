class WellnessDay < ApplicationRecord
  validates :date, presence: true, uniqueness: true
end
