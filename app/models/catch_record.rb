class CatchRecord < ApplicationRecord
  belongs_to :user

  validates :fish_size_cm, presence: true, numericality: { greater_than: 0 }
  validates :score, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
