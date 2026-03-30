class Category < ApplicationRecord
  has_and_belongs_to_many :products

  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: "parent_id", dependent: :nullify

  before_validation :generate_slug

  validates :name, :slug, presence: true
  validate :parent_is_not_self

  scope :roots, -> { where(parent_id: nil) }

  # Returns flat array of [category, depth] pairs for tree display
  def self.ordered_tree
    all_cats = order(:name).to_a
    by_parent = all_cats.group_by(&:parent_id)
    result = []
    build = ->(parent_id, depth) {
      (by_parent[parent_id] || []).each do |cat|
        result << [cat, depth]
        build.call(cat.id, depth + 1)
      end
    }
    build.call(nil, 0)
    result
  end

  def ancestor_ids
    ids = []
    current = parent
    while current
      ids << current.id
      current = current.parent
    end
    ids
  end

  private

  def generate_slug
    self.slug = name.parameterize if slug.blank? && name.present?
  end

  def parent_is_not_self
    errors.add(:parent_id, "nu poate fi propria categorie") if parent_id.present? && parent_id == id
  end
end
