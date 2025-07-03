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
  # config.assets.css_compressor = :sass
  # config.asset_host = "http://assets.example.com"

  # === FILE STORAGE ===
  config.active_storage.service = :bunny
  config.active_storage.resolve_model_to_route = :rails_storage_redirect

  config.active_storage.variant_processor = :vips
  config.active_storage.draw_routes = true
  config.active_storage.default_host = "https://ayus-cdn.b-cdn.net"
  # === DEFAULT URLS ===
  Rails.application.routes.default_url_options[:host] = "https://ag1-eef1.onrender.com"

  # === SECURITY ===
  config.force_ssl = true
  # config.assume_ssl = true
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # === LOGGING ===
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  config.log_tags = [:request_id]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # === MAILER ===
  config.action_mailer.perform_caching = false
  # config.action_mailer.raise_delivery_errors = false

  # === I18N ===
  config.i18n.fallbacks = true

  # === DATABASE & JOBS ===
  config.active_record.dump_schema_after_migration = false
  # config.active_job.queue_adapter = :resque
  # config.active_job.queue_name_prefix = "ag1_production"

  # === DEPRECATIONS ===
  config.active_support.report_deprecations = false

  # === HOSTS / DNS / HEALTH CHECKS (opțional) ===
  # config.hosts = ["example.com", /.*\.example\.com/]
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # === ACTION CABLE (opțional) ===
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]
end
