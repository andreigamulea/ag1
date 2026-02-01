# PLAN VARIANTE V6.0 - Implementation Ready

## Filozofie

**Admin poate:** Creare/dezactivare/reactivare variantă, schimbare preț/stock/SKU/combinație - oricând.

**Sistemul protejează:**
- Unicitate variantă activă per combinație
- Checkout atomic (stoc, status)
- Snapshot imutabil comenzi
- Price/stock NOT NULL și >= 0

---

## 1. MIGRĂRI

### M1: Add Columns

```ruby
class M1AddVariantsColumns < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:variants, :status)
      add_column :variants, :status, :integer, null: false, default: 0
    end
    if column_exists?(:variants, :options_digest)
      col = connection.columns(:variants).find { |c| c.name == 'options_digest' }
      change_column :variants, :options_digest, :text if col && col.type != :text
    else
      add_column :variants, :options_digest, :text
    end
    unless column_exists?(:variants, :external_sku)
      add_column :variants, :external_sku, :string
    end
    add_index :variants, :status, if_not_exists: true

    unless column_exists?(:order_items, :variant_sku)
      add_column :order_items, :variant_sku, :string
    end
    if column_exists?(:order_items, :variant_options_text)
      col = connection.columns(:order_items).find { |c| c.name == 'variant_options_text' }
      change_column :order_items, :variant_options_text, :text if col && col.type != :text
    else
      add_column :order_items, :variant_options_text, :text
    end
    unless column_exists?(:order_items, :vat_rate_snapshot)
      add_column :order_items, :vat_rate_snapshot, :decimal, precision: 5, scale: 2
    end
    unless column_exists?(:order_items, :currency)
      add_column :order_items, :currency, :string, default: 'RON'
    end
    unless column_exists?(:order_items, :line_total_gross)
      add_column :order_items, :line_total_gross, :decimal, precision: 10, scale: 2
    end
    unless column_exists?(:order_items, :tax_amount)
      add_column :order_items, :tax_amount, :decimal, precision: 10, scale: 2
    end
    change_column_null :order_items, :variant_id, true
  end
end
```

### M2: Cleanup & Preflight

```ruby
class M2CleanupVariantsData < ActiveRecord::Migration[7.0]
  def up
    # 1. Normalizare
    execute "UPDATE variants SET options_digest = NULLIF(BTRIM(options_digest), '')"
    execute "UPDATE variants SET external_sku = NULLIF(BTRIM(external_sku), '')"
    execute "UPDATE variants SET sku = BTRIM(sku) WHERE sku IS NOT NULL"
    execute "UPDATE variants SET sku = 'VAR-' || id WHERE sku IS NULL OR sku = ''"

    # 2. PREFLIGHT: SKU duplicate
    sku_duplicates = execute(<<~SQL).to_a
      SELECT product_id, sku, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants WHERE sku IS NOT NULL
      GROUP BY product_id, sku HAVING COUNT(*) > 1
    SQL
    if sku_duplicates.any?
      sku_duplicates.each { |r| puts "SKU dup: Product #{r['product_id']}, SKU '#{r['sku']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix SKU duplicates manually!" if Rails.env.production?
    end

    # 2b. PREFLIGHT: external_sku duplicate
    ext_sku_duplicates = execute(<<~SQL).to_a
      SELECT external_sku, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants WHERE external_sku IS NOT NULL
      GROUP BY external_sku HAVING COUNT(*) > 1
    SQL
    if ext_sku_duplicates.any?
      ext_sku_duplicates.each { |r| puts "External SKU dup: '#{r['external_sku']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix external_sku duplicates manually!" if Rails.env.production?
    end

    # 2c. PREFLIGHT: Variante cu multiple valori pe același option_type
    multi_value = execute(<<~SQL).to_a
      SELECT v.product_id, v.id as variant_id, ov.option_type_id,
             COUNT(DISTINCT ovv.option_value_id) as cnt,
             array_agg(DISTINCT ovv.option_value_id ORDER BY ovv.option_value_id) as value_ids
      FROM option_value_variants ovv
      JOIN variants v ON v.id = ovv.variant_id
      JOIN option_values ov ON ov.id = ovv.option_value_id
      GROUP BY v.product_id, v.id, ov.option_type_id
      HAVING COUNT(DISTINCT ovv.option_value_id) > 1
    SQL
    if multi_value.any?
      multi_value.each do |r|
        puts "Multi value: product #{r['product_id']} variant #{r['variant_id']} " \
             "type #{r['option_type_id']} cnt #{r['cnt']} values #{r['value_ids']}"
      end
      raise "ABORT: Variants have multiple values for same option_type. Fix data first." if Rails.env.production?
    end

    # 2d. DEDUPE join tables
    execute(<<~SQL)
      DELETE FROM product_option_types a
      USING product_option_types b
      WHERE a.ctid > b.ctid
        AND a.product_id = b.product_id
        AND a.option_type_id = b.option_type_id
    SQL
    execute(<<~SQL)
      DELETE FROM option_value_variants a
      USING option_value_variants b
      WHERE a.ctid > b.ctid
        AND a.variant_id = b.variant_id
        AND a.option_value_id = b.option_value_id
    SQL

    # 3. BACKFILL: Calculează digest
    execute(<<~SQL)
      UPDATE variants
      SET options_digest = subq.calculated_digest
      FROM (
        SELECT ovv.variant_id,
               string_agg(ovv.option_value_id::text, '-' ORDER BY ovv.option_value_id) AS calculated_digest
        FROM option_value_variants ovv
        JOIN variants v ON v.id = ovv.variant_id
        JOIN option_values ov ON ov.id = ovv.option_value_id
        JOIN product_option_types pot
          ON pot.product_id = v.product_id
         AND pot.option_type_id = ov.option_type_id
        GROUP BY ovv.variant_id
      ) subq
      WHERE variants.id = subq.variant_id
    SQL

    # 3b. Nullify digest pentru variante cu doar opțiuni obsolete
    execute(<<~SQL)
      UPDATE variants v
      SET options_digest = NULL
      WHERE v.options_digest IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM option_value_variants ovv
          JOIN option_values ov ON ov.id = ovv.option_value_id
          JOIN product_option_types pot
            ON pot.product_id = v.product_id
           AND pot.option_type_id = ov.option_type_id
          WHERE ovv.variant_id = v.id
        )
    SQL

    # 4. PREFLIGHT: Digest duplicate (active)
    digest_duplicates = execute(<<~SQL).to_a
      SELECT product_id, options_digest, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants
      WHERE options_digest IS NOT NULL AND status = 0
      GROUP BY product_id, options_digest HAVING COUNT(*) > 1
    SQL
    if digest_duplicates.any?
      digest_duplicates.each { |r| puts "Digest dup: Product #{r['product_id']}, '#{r['options_digest']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix digest duplicates manually!" if Rails.env.production?
    end

    # 5. CLEANUP: Dezactivează default active duplicate
    execute(<<~SQL)
      UPDATE variants SET status = 1
      WHERE id IN (
        SELECT v.id FROM variants v
        INNER JOIN (
          SELECT product_id, MIN(id) as keep_id FROM variants
          WHERE status = 0 AND options_digest IS NULL
          GROUP BY product_id HAVING COUNT(*) > 1
        ) dups ON v.product_id = dups.product_id
        WHERE v.status = 0 AND v.options_digest IS NULL AND v.id != dups.keep_id
      )
    SQL

    # 6. CLEANUP: Fix NULL/negative price/stock
    execute("UPDATE variants SET stock = 0 WHERE stock < 0 OR stock IS NULL")
    execute("UPDATE variants SET price = 0 WHERE price < 0 OR price IS NULL")

    # 6b. PREFLIGHT: status invalid (în afara enum 0/1)
    invalid_status = execute(<<~SQL).to_a
      SELECT status, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants
      WHERE status NOT IN (0, 1)
      GROUP BY status
    SQL
    if invalid_status.any?
      invalid_status.each { |r| puts "Invalid status #{r['status']}: #{r['cnt']} variants - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix invalid status values manually!" if Rails.env.production?
      # În non-prod, normalizează la inactive
      execute("UPDATE variants SET status = 1 WHERE status NOT IN (0, 1)")
    end

    # 7. CLEANUP ORFANI
    execute(<<~SQL)
      DELETE FROM option_value_variants ovv
      WHERE NOT EXISTS (SELECT 1 FROM variants v WHERE v.id = ovv.variant_id)
         OR NOT EXISTS (SELECT 1 FROM option_values ov WHERE ov.id = ovv.option_value_id)
    SQL

    execute(<<~SQL)
      DELETE FROM variants v
      WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.id = v.product_id)
        AND NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.variant_id = v.id)
    SQL

    orphans_used = execute(<<~SQL).to_a
      SELECT v.id, v.product_id, COUNT(oi.id) as order_items_count
      FROM variants v
      JOIN order_items oi ON oi.variant_id = v.id
      LEFT JOIN products p ON p.id = v.product_id
      WHERE p.id IS NULL
      GROUP BY v.id, v.product_id
    SQL
    if orphans_used.any?
      orphans_used.each { |r| puts "Orphan variant used in orders: variant #{r['id']} product_id #{r['product_id']} order_items #{r['order_items_count']}" }
      raise "ABORT: Orphan variants referenced by orders. Fix data!" if Rails.env.production?
    end

    execute(<<~SQL)
      UPDATE order_items oi
      SET variant_id = NULL
      WHERE variant_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM variants v WHERE v.id = oi.variant_id)
    SQL
  end
end
```

### M3: Constraints & Indexes

```ruby
class M3AddVariantsConstraints < ActiveRecord::Migration[7.0]
  def change
    # UNIQUE INDEXES
    add_index :variants, [:product_id, :sku], unique: true,
              name: 'idx_unique_sku_per_product', if_not_exists: true

    add_index :variants, [:product_id, :options_digest], unique: true,
              where: "options_digest IS NOT NULL AND status = 0",
              name: 'idx_unique_active_options_per_product', if_not_exists: true

    add_index :variants, [:product_id], unique: true,
              where: "options_digest IS NULL AND status = 0",
              name: 'idx_unique_active_default_variant', if_not_exists: true

    add_index :variants, :external_sku, unique: true,
              where: "external_sku IS NOT NULL",
              name: 'idx_unique_external_sku', if_not_exists: true

    # CHECK CONSTRAINTS
    unless constraint_exists?(:variants, 'chk_variants_price_positive')
      add_check_constraint :variants, 'price IS NOT NULL AND price >= 0',
                           name: 'chk_variants_price_positive'
    end
    unless constraint_exists?(:variants, 'chk_variants_stock_positive')
      add_check_constraint :variants, 'stock IS NOT NULL AND stock >= 0',
                           name: 'chk_variants_stock_positive'
    end

    # CHECK constraint pe status (doar 0=active sau 1=inactive)
    unless constraint_exists?(:variants, 'chk_variants_status_enum')
      add_check_constraint :variants, 'status IN (0, 1)',
                           name: 'chk_variants_status_enum'
    end

    # JOIN TABLE INDEXES
    add_index :option_value_variants, [:variant_id, :option_value_id], unique: true,
              name: 'idx_unique_ovv', if_not_exists: true
    add_index :option_value_variants, :variant_id, name: 'idx_ovv_variant', if_not_exists: true
    add_index :option_value_variants, :option_value_id, name: 'idx_ovv_option_value', if_not_exists: true

    # FOREIGN KEYS
    unless foreign_key_exists?(:option_value_variants, :variants)
      add_foreign_key :option_value_variants, :variants, on_delete: :cascade
    end
    unless foreign_key_exists?(:option_value_variants, :option_values)
      add_foreign_key :option_value_variants, :option_values, on_delete: :restrict
    end
    unless foreign_key_exists?(:variants, :products)
      add_foreign_key :variants, :products, on_delete: :restrict
    end
    unless foreign_key_exists?(:order_items, :variants)
      add_foreign_key :order_items, :variants, on_delete: :nullify
    end

    # PERFORMANCE INDEXES
    add_index :product_option_types, [:product_id, :option_type_id], unique: true,
              name: 'idx_unique_product_option_type', if_not_exists: true
    add_index :product_option_types, :product_id, name: 'idx_pot_product', if_not_exists: true
    add_index :option_values, :option_type_id, name: 'idx_ov_type', if_not_exists: true
  end

  private

  def constraint_exists?(table, name)
    query = <<~SQL
      SELECT 1 FROM pg_constraint
      WHERE conname = '#{name}'
        AND conrelid = '#{table}'::regclass
    SQL
    ActiveRecord::Base.connection.select_value(query).present?
  end
end
```

---

## 2. MODELE

### Variant

```ruby
class Variant < ApplicationRecord
  enum :status, { active: 0, inactive: 1 }, default: :active

  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :nullify

  validates :sku, presence: true, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }

  validate :no_active_digest_conflict, if: :should_validate_active_digest_conflict?

  before_validation :normalize_identifiers

  scope :available, -> { active }
  scope :purchasable, -> { active.complete.where('stock > 0') }
  scope :complete, -> {
    where("NOT EXISTS (
      SELECT 1 FROM product_option_types pot
      WHERE pot.product_id = variants.product_id
        AND NOT EXISTS (
          SELECT 1 FROM option_value_variants ovv
          JOIN option_values ov ON ov.id = ovv.option_value_id
          WHERE ovv.variant_id = variants.id
            AND ov.option_type_id = pot.option_type_id
        )
    )")
  }

  def deactivate!
    inactive!
  end

  def activate!
    active!
  end

  def default_variant?
    options_digest.nil?
  end

  def compute_digest_from_db
    allowed_type_ids = ProductOptionType.where(product_id: product_id).pluck(:option_type_id)
    option_value_variants
      .joins(:option_value)
      .where(option_values: { option_type_id: allowed_type_ids })
      .order(:option_value_id)
      .pluck(:option_value_id)
      .join('-')
      .presence
  end

  private

  # Rulează validarea dacă record-ul VA FI activ după save
  # și se schimbă status sau digest.
  def should_validate_active_digest_conflict?
    (will_save_change_to_status? || will_save_change_to_options_digest?) && will_be_active_after_save?
  end

  def will_be_active_after_save?
    if will_save_change_to_status?
      status_change_to_be_saved&.last == Variant.statuses[:active]
    else
      status_before_type_cast == Variant.statuses[:active]
    end
  end

  def normalize_identifiers
    self.options_digest = nil if options_digest.is_a?(String) && options_digest.strip.empty?
    self.external_sku = external_sku.strip.presence if external_sku.is_a?(String)
    self.sku = sku.strip if sku.is_a?(String)
  end

  def no_active_digest_conflict
    scope = Variant.where(product_id: product_id, status: Variant.statuses[:active]).where.not(id: id)

    conflict = if options_digest.nil?
      scope.where(options_digest: nil).exists?
    else
      scope.where(options_digest: options_digest).exists?
    end

    errors.add(:status, "Există deja o variantă activă cu această combinație") if conflict
  end
end
```

### OptionValueVariant

```ruby
class OptionValueVariant < ApplicationRecord
  belongs_to :variant
  belongs_to :option_value
end
```

### Product

```ruby
class Product < ApplicationRecord
  has_many :variants, dependent: :restrict_with_error
  has_many :product_option_types, dependent: :destroy
  has_many :option_types, through: :product_option_types

  def archive!
    transaction do
      variants.active.update_all(status: 1)
      update!(archived: true, archived_at: Time.current)
    end
  end
end
```

---

## 3. SERVICII

### Variants::CreateOrReactivateService

```ruby
module Variants
  class CreateOrReactivateService
    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true)

    def initialize(product)
      @product = product
    end

    def call(option_value_ids, attributes = {})
      option_value_ids = sanitize_ids(option_value_ids)

      # Lock pe product pentru a serializa cu UpdateOptionTypesService
      # și a evita race conditions pe option_types/digest
      @product.transaction do
        @product.lock!

        digest = option_value_ids.empty? ? nil : option_value_ids.join('-')
        desired_status = normalize_status(attributes[:status] || attributes["status"])

        return invalid("Unele opțiuni nu aparțin produsului") unless valid_option_values?(option_value_ids)

        if desired_status == :inactive
          return create_new(option_value_ids, attributes)
        end

        existing = find_existing_variant(digest)

        if existing
          handle_existing(existing, attributes)
        else
          create_new(option_value_ids, attributes)
        end
      end
    rescue ActiveRecord::RecordNotUnique => e
      handle_unique_violation(e, option_value_ids.empty? ? nil : option_value_ids.join('-'))
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, variant: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    end

    private

    def handle_unique_violation(exception, digest)
      msg = exception.cause&.message.to_s

      if msg.include?('idx_unique_sku_per_product')
        return Result.new(success: false, variant: nil, action: :invalid,
                          error: "SKU deja folosit pentru acest produs")
      end

      if msg.include?('idx_unique_external_sku')
        return Result.new(success: false, variant: nil, action: :invalid,
                          error: "External SKU deja folosit")
      end

      if msg.include?('idx_unique_active_options_per_product')
        return Result.new(success: false, variant: nil, action: :conflict,
                          error: "Există deja o variantă activă cu această combinație de opțiuni")
      end

      if msg.include?('idx_unique_active_default_variant')
        return Result.new(success: false, variant: nil, action: :conflict,
                          error: "Există deja o variantă default activă pentru acest produs")
      end

      handle_race_condition(exception, digest)
    end

    def sanitize_ids(input)
      Array(input).map { |x| x.to_s.strip }.reject(&:empty?).map(&:to_i).reject(&:zero?).uniq.sort
    end

    def valid_option_values?(ids)
      return true if ids.empty?

      rows = OptionValue.where(id: ids).pluck(:id, :option_type_id)
      return false if rows.size != ids.size

      type_ids = rows.map(&:last)
      return false if type_ids.size != type_ids.uniq.size

      allowed = ProductOptionType.where(product_id: @product.id).pluck(:option_type_id)
      (type_ids - allowed).empty?
    end

    # NOTE: query direct pe Variant ca să evităm cache-ul asociației @product.variants
    def find_existing_variant(digest)
      scope = Variant.where(product_id: @product.id)
      if digest.nil?
        scope.find_by(options_digest: nil, status: :active) ||
          scope.where(options_digest: nil).order(:id).first
      else
        scope.find_by(options_digest: digest, status: :active) ||
          scope.where(options_digest: digest).order(:id).first
      end
    end

    def handle_existing(existing, attributes)
      desired_status = normalize_status(attributes[:status] || attributes["status"])
      # Blochează options_digest din attributes - digest-ul se setează doar prin servicii
      safe_attrs = attributes.except(:options_digest, "options_digest", :status, "status")

      if existing.active?
        Result.new(success: false, variant: existing, action: :already_exists,
                   error: "Combinația există deja și e activă (SKU: #{existing.sku})")
      else
        existing.update!(safe_attrs.merge(status: desired_status))
        Result.new(success: true, variant: existing, action: :reactivated, error: nil)
      end
    end

    def create_new(option_value_ids, attributes)
      desired_status = normalize_status(attributes[:status] || attributes["status"])

      # Tranzacția externă (din call) deja ține lock pe product
      variant = @product.variants.create!(attributes.merge(status: :inactive, options_digest: nil))
      option_value_ids.each { |id| variant.option_value_variants.create!(option_value_id: id) }

      new_digest = option_value_ids.empty? ? nil : option_value_ids.join('-')
      variant.update!(options_digest: new_digest, status: desired_status)

      Result.new(success: true, variant: variant, action: :created, error: nil)
    end

    def handle_race_condition(exception, digest)
      existing = find_existing_variant(digest)
      if existing
        Result.new(success: false, variant: existing, action: :race_condition,
                   error: "Combinația a fost creată de alt proces")
      else
        raise exception
      end
    end

    def invalid(message)
      Result.new(success: false, variant: nil, action: :invalid, error: message)
    end

    def normalize_status(val)
      return :active if val.nil? || (val.respond_to?(:empty?) && val.empty?)
      return Variant.statuses.key(val)&.to_sym || :active if val.is_a?(Integer)
      s = val.to_s
      Variant.statuses.key?(s) ? s.to_sym : :active
    end
  end
end
```

### Variants::UpdateOptionsService

```ruby
module Variants
  class UpdateOptionsService
    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true)

    def initialize(variant)
      @variant = variant
      @product = variant.product
    end

    def call(new_option_value_ids)
      new_option_value_ids = sanitize_ids(new_option_value_ids)

      # Lock pe product pentru a serializa cu UpdateOptionTypesService
      @product.transaction do
        @product.lock!
        @variant.lock!

        # Validare sub lock pentru a evita race condition pe option_types
        unless valid_option_values?(new_option_value_ids)
          return Result.new(success: false, variant: @variant, action: :invalid,
                           error: "Unele opțiuni nu aparțin acestui produs")
        end

        new_digest = new_option_value_ids.empty? ? nil : new_option_value_ids.join('-')

        # NOTE: query direct pe Variant ca să evităm cache-ul asociației product.variants
        if @variant.active?
          conflict = Variant.where(product_id: @product.id)
                            .where.not(id: @variant.id)
                            .find_by(options_digest: new_digest, status: :active)
          if conflict
            return Result.new(success: false, variant: conflict, action: :conflict,
                             error: "Există deja o variantă activă cu această combinație (SKU: #{conflict.sku})")
          end
        end

        @variant.option_value_variants.destroy_all
        new_option_value_ids.each { |id| @variant.option_value_variants.create!(option_value_id: id) }

        @variant.update!(options_digest: new_digest)
      end

      Result.new(success: true, variant: @variant, action: :updated, error: nil)
    rescue ActiveRecord::RecordNotUnique => e
      Result.new(success: false, variant: @variant, action: :conflict,
                 error: "Există deja o variantă activă cu această combinație")
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, variant: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    end

    private

    def sanitize_ids(input)
      Array(input).map { |x| x.to_s.strip }.reject(&:empty?).map(&:to_i).reject(&:zero?).uniq.sort
    end

    def valid_option_values?(ids)
      return true if ids.empty?

      rows = OptionValue.where(id: ids).pluck(:id, :option_type_id)
      return false if rows.size != ids.size

      type_ids = rows.map(&:last)
      return false if type_ids.size != type_ids.uniq.size

      allowed = ProductOptionType.where(product_id: @product.id).pluck(:option_type_id)
      (type_ids - allowed).empty?
    end
  end
end
```

### Products::UpdateOptionTypesService

```ruby
module Products
  class UpdateOptionTypesService
    def initialize(product)
      @product = product
    end

    def call(new_option_type_ids)
      @product.transaction do
        @product.lock!
        @product.option_type_ids = new_option_type_ids

        variants = @product.variants.lock.to_a

        new_digest_by_id = {}
        variants.each do |v|
          new_digest_by_id[v.id] = v.compute_digest_from_db
        end

        keep_active_ids = []
        variants.group_by { |v| new_digest_by_id[v.id] }.each do |_digest, group|
          active_in_group = group.select(&:active?)
          if active_in_group.any?
            keep_active_ids << active_in_group.min_by(&:id).id
          end
        end

        deactivated_ids = []
        variants.each do |v|
          next unless v.active?
          next if keep_active_ids.include?(v.id)
          v.update_column(:status, Variant.statuses[:inactive])
          deactivated_ids << v.id
        end

        variants.each do |v|
          nd = new_digest_by_id[v.id]
          v.update_column(:options_digest, nd) if v.options_digest != nd
        end

        { success: true, deactivated_count: deactivated_ids.size, deactivated_ids: deactivated_ids }
      end
    end
  end
end
```

### Checkout::FinalizeService

```ruby
module Checkout
  class FinalizeService
    class VariantUnavailableError < StandardError; end
    class InsufficientStockError < StandardError; end
    class AlreadyFinalizedError < StandardError; end

    def initialize(order)
      @order = order
    end

    def call
      @order.transaction do
        @order.lock!
        raise AlreadyFinalizedError, "Comanda a fost deja procesată" unless @order.status == 'pending'

        items = @order.order_items.lock.order(:id).to_a

        if items.any? { |i| i.variant_id.nil? }
          raise VariantUnavailableError, "Comanda conține item fără variantă"
        end

        items_by_variant = items.group_by(&:variant_id)
        sorted_ids = items_by_variant.keys.compact.sort

        sorted_ids.each do |variant_id|
          variant_items = items_by_variant[variant_id]
          total_qty = variant_items.sum(&:quantity)

          rows = Variant
            .where(id: variant_id, status: :active)
            .where('stock >= ?', total_qty)
            .update_all(['stock = stock - ?', total_qty])

          if rows == 0
            variant = Variant.find_by(id: variant_id)
            raise VariantUnavailableError, "Varianta nu e disponibilă" unless variant&.active?
            raise InsufficientStockError, "Stoc insuficient pentru '#{variant.sku}'"
          end

          variant = Variant.find(variant_id)
          variant_items.each { |item| snapshot_item(item, variant) }
        end

        @order.update!(status: 'confirmed')
      end
    end

    private

    def snapshot_item(item, variant)
      options_text = variant.option_values.order(:id).pluck(:name).join(', ')

      item.update!(
        variant_sku: variant.sku,
        variant_options_text: options_text,
        vat_rate_snapshot: variant.vat_rate,
        line_total_gross: item.quantity * variant.price
      )
    end
  end
end
```

### Orders::ConcurrencyPolicy (Helper)

```ruby
module Orders
  module ConcurrencyPolicy
    def with_locked_items!(order)
      order.transaction do
        order.lock!
        items = order.order_items.lock.order(:id).to_a
        yield(items)
      end
    end
  end
end
```

---

## 4. RAKE TASK: Audit

```ruby
namespace :variants do
  desc "Audit variants data"
  task audit: :environment do
    puts "=== VARIANTS AUDIT ==="

    sku_dups = Variant.where.not(sku: nil).group(:product_id, :sku).having('COUNT(*) > 1').count
    puts sku_dups.any? ? "❌ SKU duplicates: #{sku_dups.count}" : "✅ No SKU duplicates"

    if Variant.column_names.include?('options_digest')
      digest_dups = Variant.where(status: 0).where.not(options_digest: nil)
                           .group(:product_id, :options_digest).having('COUNT(*) > 1').count
      puts digest_dups.any? ? "❌ Active digest duplicates: #{digest_dups.count}" : "✅ No active digest duplicates"
    end

    puts Variant.where('stock < 0').exists? ? "❌ Negative stock" : "✅ No negative stock"
    puts Variant.where('price < 0').exists? ? "❌ Negative price" : "✅ No negative price"
    puts Variant.where(stock: nil).exists? ? "❌ NULL stock" : "✅ No NULL stock"
    puts Variant.where(price: nil).exists? ? "❌ NULL price" : "✅ No NULL price"

    puts "=== END AUDIT ==="
  end
end
```

---

## 5. INVARIANTE

```
1. O COMBINAȚIE ACTIVĂ = O SINGURĂ VARIANTĂ ACTIVĂ
2. MAXIM 1 DEFAULT ACTIV PER PRODUS (digest NULL + status active)
3. COMBINAȚIA POATE FI SCHIMBATĂ ORICÂND
4. CUMPĂRABIL = active + complete + stock > 0
4b. CHECKOUT PERMITE = active + stock >= qty
5. STOCUL NU POATE FI DEPĂȘIT (checkout atomic)
6. COMANDA = IMUTABILĂ (snapshot)
7. PRICE/STOCK NOT NULL ȘI >= 0
8. DIGEST SE CALCULEAZĂ EXPLICIT ÎN SERVICII
9. MULTIPLE DRAFT-URI CU ACELAȘI DIGEST = PERMIS (dar max 1 ACTIVE)
```

---

## 6. PAȘI DEPLOY

1. `rails variants:audit` - verifică starea
2. `rails db:migrate` (M1) - adaugă coloane
3. `rails db:migrate` (M2) - cleanup
4. `rails db:migrate` (M3) - constraints
5. Deploy cod
6. `rails variants:audit` - verificare finală


## asta e o varianta buna inainte de import feed-uri