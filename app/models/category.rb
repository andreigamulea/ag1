class Category < ApplicationRecord
  has_and_belongs_to_many :products

  before_validation :generate_slug

  validates :name, :slug, presence: true

  private

  def generate_slug
    self.slug = name.parameterize if slug.blank? && name.present?
  end
end
