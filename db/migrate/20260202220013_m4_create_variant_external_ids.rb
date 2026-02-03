# frozen_string_literal: true

class M4CreateVariantExternalIds < ActiveRecord::Migration[7.1]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # UNIVERSAL: Table creation + indexes (funcționează pe orice DB)
    # ═══════════════════════════════════════════════════════════════════════════

    create_table :variant_external_ids do |t|
      # index: false - evităm index duplicat (adăugăm manual mai jos cu nume explicit)
      t.references :variant, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :source, null: false         # ex: "erp", "emag", "supplier_x"
      t.string :source_account, null: false, default: 'default'  # ex: "emag_ro_1", "erp_company_a"
      t.string :external_id, null: false    # ID-ul din sursa externă
      t.string :external_sku                # SKU-ul din sursa externă (opțional)

      t.timestamps
    end

    # Unicitate per sursă + cont + external_id
    # Permite: (emag, emag_ro_1, 123) și (emag, emag_ro_2, 123) să coexiste
    add_index :variant_external_ids, [:source, :source_account, :external_id], unique: true,
              name: 'idx_unique_source_account_external_id'

    # Pentru lookup rapid după variant
    add_index :variant_external_ids, :variant_id, name: 'idx_vei_variant'

    # Pentru căutare după source (când vrei toate variantele din ERP etc.)
    add_index :variant_external_ids, :source, name: 'idx_vei_source'

    # Pentru căutare după source + account
    add_index :variant_external_ids, [:source, :source_account], name: 'idx_vei_source_account'

    # ═══════════════════════════════════════════════════════════════════════════
    # POSTGRES-ONLY: CHECK constraints cu regex și btrim()
    # Pe non-Postgres, validările Rails din model asigură aceeași integritate
    # ═══════════════════════════════════════════════════════════════════════════
    return unless connection.adapter_name =~ /postgres/i

    # CHECK: source trebuie să fie lowercase (normalizare la nivel DB)
    # Format: lowercase letter + alphanumeric/underscore, max 50 chars
    add_check_constraint :variant_external_ids,
      "source ~ '^[a-z][a-z0-9_]{0,49}$'",
      name: 'chk_vei_source_format'

    # CHECK: source_account trebuie să fie lowercase
    add_check_constraint :variant_external_ids,
      "source_account ~ '^[a-z][a-z0-9_]{0,49}$'",
      name: 'chk_vei_source_account_format'

    # CHECK: external_id nu poate fi empty/whitespace
    add_check_constraint :variant_external_ids,
      "btrim(external_id) <> ''",
      name: 'chk_vei_external_id_not_empty'

    # CHECK: external_id normalizat (fără leading/trailing whitespace)
    add_check_constraint :variant_external_ids,
      "external_id = btrim(external_id)",
      name: 'chk_vei_external_id_normalized'
  end
end
