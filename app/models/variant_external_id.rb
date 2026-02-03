# frozen_string_literal: true

class VariantExternalId < ApplicationRecord
  belongs_to :variant

  # Validări
  validates :source, presence: true
  validates :source_account, presence: true
  validates :external_id, presence: true

  # Format validations (match Postgres CHECK constraints)
  validates :source, format: {
    with: /\A[a-z][a-z0-9_]{0,49}\z/,
    message: 'must be lowercase, start with letter, contain only letters/numbers/underscores (max 50 chars)'
  }
  validates :source_account, format: {
    with: /\A[a-z][a-z0-9_]{0,49}\z/,
    message: 'must be lowercase, start with letter, contain only letters/numbers/underscores (max 50 chars)'
  }

  # Unicitate per source + account + external_id
  validates :external_id, uniqueness: { scope: [:source, :source_account] }

  # Normalizare înainte de validare
  before_validation :normalize_attributes

  # Scopes pentru căutare
  scope :by_source, ->(source) { where(source: source) }
  scope :by_source_account, ->(source, account) { where(source: source, source_account: account) }

  # Single source of truth pentru normalizare lookup params.
  # Folosit de AdminExternalIdService si alte servicii care fac lookup/find_by.
  # DRY: Orice schimbare de normalizare se face doar aici.
  #
  # @return [Hash] cu keys :source, :source_account, :external_id (nil-safe, compact)
  def self.normalize_lookup(source:, external_id:, source_account: 'default')
    {
      source: source.to_s.strip.downcase.presence,
      source_account: (source_account.to_s.strip.downcase.presence || 'default'),
      external_id: external_id.to_s.strip.presence
    }.compact
  end

  # Găsește variant după external_id
  def self.find_variant(source:, external_id:, source_account: 'default')
    find_by(source: source, source_account: source_account, external_id: external_id.to_s.strip)&.variant
  end

  private

  def normalize_attributes
    self.source = source.to_s.strip.downcase if source.present?
    self.source_account = source_account.to_s.strip.downcase if source_account.present?
    self.external_id = external_id.to_s.strip if external_id.present?
    self.external_sku = external_sku.to_s.strip.presence if external_sku.present?
  end
end
