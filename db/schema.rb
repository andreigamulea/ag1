# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_03_31_130004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "cart_snapshots", force: :cascade do |t|
    t.bigint "user_id"
    t.string "email"
    t.string "session_id"
    t.jsonb "cart_data"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_cart_snapshots_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.string "meta_title"
    t.string "meta_description"
    t.bigint "parent_id"
    t.index ["parent_id"], name: "index_categories_on_parent_id"
  end

  create_table "categories_products", id: false, force: :cascade do |t|
    t.bigint "category_id", null: false
    t.bigint "product_id", null: false
    t.index ["category_id", "product_id"], name: "index_categories_products_on_category_id_and_product_id"
    t.index ["product_id", "category_id"], name: "index_categories_products_on_product_id_and_category_id"
  end

  create_table "coupons", force: :cascade do |t|
    t.string "code"
    t.string "discount_type"
    t.decimal "discount_value"
    t.boolean "active"
    t.datetime "starts_at"
    t.datetime "expires_at"
    t.integer "usage_limit"
    t.integer "usage_count"
    t.decimal "minimum_cart_value"
    t.integer "minimum_quantity"
    t.integer "product_id"
    t.boolean "free_shipping"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.integer "invoice_number"
    t.datetime "emitted_at"
    t.string "status"
    t.decimal "total"
    t.decimal "vat_amount"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "series"
    t.datetime "due_date"
    t.string "payment_method"
    t.string "currency", default: "RON"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["order_id"], name: "index_invoices_on_order_id"
  end

  create_table "judets", force: :cascade do |t|
    t.string "oasp"
    t.string "denjud"
    t.string "cod"
    t.integer "idjudet"
    t.string "cod_j"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "localitatis", force: :cascade do |t|
    t.string "cod"
    t.integer "judetid"
    t.string "denumire"
    t.string "denj"
    t.string "abr"
    t.string "cod_vechi"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "memory_logs", force: :cascade do |t|
    t.float "used_mb"
    t.float "available_mb"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "used_memory_mb"
    t.float "freed_memory_mb"
    t.float "reclaimed_mb"
    t.string "notes"
  end

  create_table "mobility_string_translations", force: :cascade do |t|
    t.string "locale", null: false
    t.string "key", null: false
    t.string "value"
    t.integer "translatable_id", null: false
    t.string "translatable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["translatable_id", "translatable_type", "key", "locale"], name: "index_mobility_string_translations_on_keys", unique: true
    t.index ["translatable_id", "translatable_type", "locale"], name: "index_mobility_string_translations_on_translatable"
  end

  create_table "mobility_text_translations", force: :cascade do |t|
    t.string "locale", null: false
    t.string "key", null: false
    t.text "value"
    t.integer "translatable_id", null: false
    t.string "translatable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["translatable_id", "translatable_type", "key", "locale"], name: "index_mobility_text_translations_on_keys", unique: true
    t.index ["translatable_id", "translatable_type", "locale"], name: "index_mobility_text_translations_on_translatable"
  end

  create_table "newsletters", force: :cascade do |t|
    t.string "nume"
    t.string "email"
    t.boolean "validat"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "option_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "presentation"
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_option_types_on_name", unique: true
  end

  create_table "option_value_variants", force: :cascade do |t|
    t.bigint "variant_id", null: false
    t.bigint "option_value_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["option_value_id"], name: "idx_ovv_option_value"
    t.index ["option_value_id"], name: "index_option_value_variants_on_option_value_id"
    t.index ["variant_id", "option_value_id"], name: "idx_unique_ovv", unique: true
    t.index ["variant_id"], name: "idx_ovv_variant"
    t.index ["variant_id"], name: "index_option_value_variants_on_variant_id"
  end

  create_table "option_values", force: :cascade do |t|
    t.bigint "option_type_id", null: false
    t.string "name", null: false
    t.string "presentation"
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "color_hex"
    t.index ["option_type_id", "name"], name: "index_option_values_on_option_type_id_and_name", unique: true
    t.index ["option_type_id"], name: "idx_ov_type"
    t.index ["option_type_id"], name: "index_option_values_on_option_type_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id"
    t.integer "quantity"
    t.decimal "price"
    t.decimal "vat"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "product_name"
    t.decimal "unit_price"
    t.decimal "total_price"
    t.bigint "variant_id"
    t.string "variant_sku"
    t.text "variant_options_text"
    t.decimal "vat_rate_snapshot", precision: 5, scale: 2
    t.string "currency", default: "RON"
    t.decimal "line_total_gross", precision: 10, scale: 2
    t.decimal "tax_amount", precision: 10, scale: 2
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
    t.index ["variant_id"], name: "index_order_items_on_variant_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "user_id"
    t.string "email"
    t.string "name"
    t.string "phone"
    t.text "address"
    t.string "city"
    t.string "postal_code"
    t.string "country"
    t.decimal "total"
    t.string "status"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "vat_amount"
    t.datetime "placed_at"
    t.string "first_name"
    t.string "last_name"
    t.string "company_name"
    t.string "cui"
    t.string "cnp"
    t.string "county"
    t.string "street"
    t.string "street_number"
    t.text "block_details"
    t.string "shipping_first_name"
    t.string "shipping_last_name"
    t.string "shipping_company_name"
    t.string "shipping_country"
    t.string "shipping_county"
    t.string "shipping_city"
    t.string "shipping_street"
    t.string "shipping_street_number"
    t.text "shipping_block_details"
    t.string "shipping_postal_code"
    t.string "shipping_phone"
    t.bigint "coupon_id"
    t.string "stripe_session_id"
    t.index ["coupon_id"], name: "index_orders_on_coupon_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "product_option_types", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "option_type_id", null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "primary", default: false, null: false
    t.index ["option_type_id"], name: "index_product_option_types_on_option_type_id"
    t.index ["product_id", "option_type_id"], name: "idx_unique_product_option_type", unique: true
    t.index ["product_id"], name: "idx_pot_product"
    t.index ["product_id"], name: "index_product_option_types_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "description_title"
    t.text "description"
    t.decimal "price", precision: 10, scale: 2
    t.decimal "cost_price", precision: 10, scale: 2
    t.decimal "discount_price", precision: 10, scale: 2
    t.string "sku", null: false
    t.integer "stock", default: 0
    t.boolean "track_inventory", default: true
    t.string "stock_status", default: "in_stock"
    t.boolean "sold_individually", default: false
    t.date "available_on"
    t.date "discontinue_on"
    t.decimal "height", precision: 8, scale: 2
    t.decimal "width", precision: 8, scale: 2
    t.decimal "depth", precision: 8, scale: 2
    t.decimal "weight", precision: 8, scale: 2
    t.string "meta_title"
    t.string "meta_description"
    t.string "meta_keywords"
    t.string "status", default: "active"
    t.boolean "featured", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "custom_attributes", default: {}, null: false
    t.boolean "requires_login", default: false
    t.string "product_type", default: "physical"
    t.string "delivery_method", default: "shipping"
    t.boolean "visible_to_guests", default: true
    t.boolean "taxable", default: false
    t.boolean "coupon_applicable", default: true
    t.string "brand"
    t.integer "views_count", default: 0
    t.string "external_image_url"
    t.text "external_image_urls", default: [], array: true
    t.text "external_file_urls", default: [], array: true
    t.decimal "vat", precision: 4, scale: 2, default: "0.0"
    t.boolean "promo_active", default: false, null: false
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "taris", force: :cascade do |t|
    t.string "nume"
    t.string "abr"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tax_rates", force: :cascade do |t|
    t.string "country_code", null: false
    t.string "country_name"
    t.decimal "rate", precision: 5, scale: 2, null: false
    t.string "category", default: "standard"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code", "category"], name: "index_tax_rates_on_country_code_and_category", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "variant_external_ids", force: :cascade do |t|
    t.bigint "variant_id", null: false
    t.string "source", null: false
    t.string "source_account", default: "default", null: false
    t.string "external_id", null: false
    t.string "external_sku"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "source_account", "external_id"], name: "idx_unique_source_account_external_id", unique: true
    t.index ["source", "source_account"], name: "idx_vei_source_account"
    t.index ["source"], name: "idx_vei_source"
    t.index ["variant_id"], name: "idx_vei_variant"
    t.check_constraint "btrim(external_id::text) <> ''::text", name: "chk_vei_external_id_not_empty"
    t.check_constraint "external_id::text = btrim(external_id::text)", name: "chk_vei_external_id_normalized"
    t.check_constraint "source::text ~ '^[a-z][a-z0-9_]{0,49}$'::text", name: "chk_vei_source_format"
    t.check_constraint "source_account::text ~ '^[a-z][a-z0-9_]{0,49}$'::text", name: "chk_vei_source_account_format"
  end

  create_table "variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "sku", null: false
    t.decimal "price", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "stock", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "options_digest"
    t.string "external_sku"
    t.decimal "vat_rate", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "external_image_url"
    t.text "external_image_urls", default: [], array: true
    t.decimal "discount_price", precision: 10, scale: 2
    t.boolean "promo_active", default: false, null: false
    t.decimal "cost_price", precision: 10, scale: 2
    t.integer "height"
    t.integer "width"
    t.integer "depth"
    t.integer "weight"
    t.string "ean"
    t.string "description_title"
    t.text "description"
    t.index ["ean"], name: "idx_unique_ean", unique: true, where: "((ean IS NOT NULL) AND ((ean)::text <> ''::text))"
    t.index ["external_sku"], name: "idx_unique_external_sku", unique: true, where: "(external_sku IS NOT NULL)"
    t.index ["product_id", "options_digest"], name: "idx_unique_active_options_per_product", unique: true, where: "((options_digest IS NOT NULL) AND (status = 0))"
    t.index ["product_id", "sku"], name: "idx_unique_sku_per_product", unique: true
    t.index ["product_id"], name: "idx_unique_active_default_variant", unique: true, where: "((options_digest IS NULL) AND (status = 0))"
    t.index ["product_id"], name: "index_variants_on_product_id"
    t.index ["status"], name: "index_variants_on_status"
    t.check_constraint "price IS NOT NULL AND price >= 0::numeric", name: "chk_variants_price_positive"
    t.check_constraint "status = ANY (ARRAY[0, 1])", name: "chk_variants_status_enum"
    t.check_constraint "stock IS NOT NULL AND stock >= 0", name: "chk_variants_stock_positive"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cart_snapshots", "users"
  add_foreign_key "categories", "categories", column: "parent_id", on_delete: :nullify
  add_foreign_key "invoices", "orders"
  add_foreign_key "option_value_variants", "option_values", on_delete: :restrict
  add_foreign_key "option_value_variants", "variants", on_delete: :cascade
  add_foreign_key "option_values", "option_types"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "order_items", "variants", on_delete: :nullify
  add_foreign_key "orders", "coupons"
  add_foreign_key "orders", "users"
  add_foreign_key "product_option_types", "option_types"
  add_foreign_key "product_option_types", "products"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "variant_external_ids", "variants", on_delete: :cascade
  add_foreign_key "variants", "products", on_delete: :restrict
end
