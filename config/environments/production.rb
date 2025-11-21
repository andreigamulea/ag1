require "active_support/core_ext/integer/time"

Rails.application.configure do
  # === CORE ===
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  # === CACHING ===
  config.action_controller.perform_caching = true

  # === STATIC FILES ===
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # === ASSETS ===
  config.assets.compile = false

  # === FILE STORAGE ===
  config.active_storage.service = :bunny
  config.active_storage.resolve_model_to_route = :rails_storage_redirect
  config.active_storage.variant_processor = :vips
  config.active_storage.draw_routes = true
  config.active_storage.default_host = "https://ayus-cdn.b-cdn.net"
  
  # === DEFAULT URLS ===
  Rails.application.routes.default_url_options[:host] = "https://ayus-cdn.b-cdn.net"  # ← RĂMÂNE NESCHIMBAT

  # === ACTIVE JOB ===
  config.active_job.queue_adapter = :async
  config.active_job.queue_name_prefix = "low_priority"

  # === SECURITY ===
  config.force_ssl = true

  # === LOGGING ===
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  config.log_tags = [:request_id]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # === MAILER - PRODUCTION cu ClausWeb SMTP ===
  config.action_mailer.perform_caching = false
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = true
  
  # URL-uri DOAR pentru link-uri din email-uri (separat de routes)
  config.action_mailer.default_url_options = {
    host: "ayus.ro",
    protocol: "https" 
  }

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: "mail.ayus.ro",
    port: 465,
    authentication: :plain,
    user_name: "comenzi@ayus.ro",
    password: Rails.application.credentials[:email_password],
    domain: "ayus.ro",
    ssl: true,
    enable_starttls_auto: false,
    open_timeout: 10,
    read_timeout: 10
  }

  # === I18N ===
  config.i18n.fallbacks = true

  # === DATABASE & JOBS ===
  config.active_record.dump_schema_after_migration = false

  # === DEPRECATIONS ===
  config.active_support.report_deprecations = false
end