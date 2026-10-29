require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Chartlek
  class Application < Rails::Application
    def self.encryption_key(name, env = ENV)
      explicit = env["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"]
      secret = env["SECRET_KEY_BASE"]

      if explicit.present?
        explicit
      elsif secret.present?
        ActiveSupport::KeyGenerator.new(secret, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256).generate_key("active_record_encryption.#{name}", 32).unpack1("H*")
      end
    end

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.middleware.insert_before ActionDispatch::Static, Rack::Deflater

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
    config.active_record.encryption.primary_key = encryption_key("primary_key")
    config.active_record.encryption.deterministic_key = encryption_key("deterministic_key")
    config.active_record.encryption.key_derivation_salt = encryption_key("key_derivation_salt")
    config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + [IPAddr.new("100.64.0.0/10")]
  end
end
