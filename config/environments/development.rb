require "active_support/core_ext/integer/time"

Rails.application.configure do
  # === RAILS CORE ===
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # === CACHING ===
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.cache_store = :memory_store
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false
    config.cache_store = :null_store
  end

  # === FILES / UPLOADS ===
  config.active_storage.service = :bunny
  config.active_storage.resolve_model_to_route = :rails_storage_proxy
  config.active_storage.variant_processor = :vips
  config.active_storage.draw_routes = true

  # === MAILER ===
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false

  # === DEPRECATIONS & LOGGING ===
  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_job.verbose_enqueue_logs = true

  # === ASSETS ===
  config.assets.quiet = true

  # === ACTION CONTROLLER ===
  config.action_controller.raise_on_missing_callback_actions = true

  # === DEFAULT URL OPTIONS ===
  Rails.application.routes.default_url_options[:host] = "localhost:3000"

  # === OPTIONALS ===
  # config.i18n.raise_on_missing_translations = true
  # config.action_view.annotate_rendered_view_with_filenames = true
  # config.action_cable.disable_request_forgery_protection = true
end
