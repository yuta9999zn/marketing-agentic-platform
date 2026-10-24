require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # ── Email giao dịch ────────────────────────────────────────────────────────
  # Cấu hình bằng biến môi trường, không hard-code. Chưa khai SMTP_HOST thì
  # dùng adapter :test — mail được soạn nhưng KHÔNG gửi đi đâu. Như vậy triển
  # khai lần đầu không im lặng gửi mail ra ngoài khi chưa ai cấu hình.
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost"),
                                               protocol: "https" }
  config.action_mailer.raise_delivery_errors = ENV["SMTP_HOST"].present?

  if ENV["SMTP_HOST"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_HOST"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USER"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: ENV["SMTP_USER"].present? ? :plain : nil,
      enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true"
    }.compact
  else
    config.action_mailer.delivery_method = :test
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Chặn tấn công qua header Host / DNS rebinding. Chỉ bật khi APP_HOST được
  # khai — VPS mới dựng chưa có tên miền vẫn truy cập được bằng IP.
  if ENV["APP_HOST"].present?
    config.hosts = [ENV["APP_HOST"], ".#{ENV['APP_HOST']}"]
    config.hosts << ENV["APP_HOST_EXTRA"] if ENV["APP_HOST_EXTRA"].present?
    # Health check phải luôn gọi được (Docker healthcheck dùng IP nội bộ).
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end

end
