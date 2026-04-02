class Feed < ApplicationRecord
  FEED_TYPES = {
    'rss' => 'RSS / Atom',
    'json' => 'JSON Feed',
    'google_shopping' => 'Google Shopping XML',
    'facebook' => 'Facebook Catalog CSV',
    'csv' => 'CSV Export'
  }.freeze

  FORMAT_TYPES = {
    'xml' => 'XML',
    'json' => 'JSON',
    'csv' => 'CSV'
  }.freeze

  enum :status, { active: 0, inactive: 1 }, default: :active

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  before_validation :set_format_from_type, if: -> { feed_type_changed? }

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :feed_type, presence: true, inclusion: { in: FEED_TYPES.keys }
  validates :format_type, presence: true, inclusion: { in: FORMAT_TYPES.keys }
  validates :products_limit, numericality: { greater_than: 0, allow_nil: true }

  def products
    scope = Product.where(status: 'active')
    scope = scope.where(stock_status: :in_stock) unless include_out_of_stock
    if selected_category_ids.any?
      scope = scope.joins(:categories).where(categories: { id: selected_category_ids }).distinct
    end
    scope = scope.limit(products_limit) if products_limit.present?
    scope.order(updated_at: :desc)
  end

  def selected_category_ids
    return [] if category_ids.blank?
    category_ids.split(',').map(&:strip).select(&:present?).map(&:to_i)
  end

  def selected_category_ids=(ids)
    self.category_ids = Array(ids).reject(&:blank?).join(',')
  end

  def feed_url(host:)
    case feed_type
    when 'csv', 'facebook'
      "/feeds/#{slug}.csv"
    when 'json'
      "/feeds/#{slug}.json"
    else
      "/feeds/#{slug}.xml"
    end
  end

  def content_type
    case format_type
    when 'json' then 'application/json'
    when 'csv' then 'text/csv'
    else 'application/xml'
    end
  end

  def touch_generated!
    update_column(:last_generated_at, Time.current)
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end

  def set_format_from_type
    self.format_type = case feed_type
    when 'json' then 'json'
    when 'csv', 'facebook' then 'csv'
    else 'xml'
    end
  end
end
