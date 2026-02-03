# frozen_string_literal: true

namespace :variants do
  desc "Audit variants data: detect duplicates, constraint violations, orphan mappings"
  task audit: :environment do
    puts "=== VARIANTS AUDIT ==="

    sku_dups = Variant.where.not(sku: nil).group(:product_id, :sku).having('COUNT(*) > 1').count
    puts sku_dups.any? ? "SKU duplicates: #{sku_dups.count}" : "No SKU duplicates"

    if Variant.column_names.include?('options_digest')
      digest_dups = Variant.where(status: 0).where.not(options_digest: nil)
                           .group(:product_id, :options_digest).having('COUNT(*) > 1').count
      puts digest_dups.any? ? "Active digest duplicates: #{digest_dups.count}" : "No active digest duplicates"
    end

    puts Variant.where('stock < 0').exists? ? "Negative stock" : "No negative stock"
    puts Variant.where('price < 0').exists? ? "Negative price" : "No negative price"
    puts Variant.where(stock: nil).exists? ? "NULL stock" : "No NULL stock"
    puts Variant.where(price: nil).exists? ? "NULL price" : "No NULL price"

    if ActiveRecord::Base.connection.table_exists?('variant_external_ids')
      orphan_mappings = VariantExternalId.left_joins(:variant).where(variants: { id: nil }).count
      puts orphan_mappings > 0 ? "Orphan external ID mappings: #{orphan_mappings}" : "No orphan external ID mappings"

      by_source = VariantExternalId.group(:source).count
      puts "External IDs by source: #{by_source}"

      by_source_account = VariantExternalId.group(:source, :source_account).count
      puts "External IDs by source+account: #{by_source_account}"

      variants_without_mapping = Variant.left_joins(:external_ids)
                                        .where(variant_external_ids: { id: nil }).count
      puts "Variants without external mapping: #{variants_without_mapping}"
    end

    puts "=== END AUDIT ==="
  end
end
