require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

module AimHelmRailsTestApp
  class Application < Rails::Application
    config.load_defaults 8.1
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.action_controller.include_all_helpers = false
    config.action_controller.allow_forgery_protection = false
    config.action_dispatch.show_exceptions = :none
    config.hosts = []
    config.secret_key_base = "aim-helm-rails-test-secret-key-base"
    config.active_record.encryption.primary_key = "aim-helm-rails-test-primary-key"
    config.active_record.encryption.deterministic_key = "aim-helm-rails-test-deterministic-key"
    config.active_record.encryption.key_derivation_salt = "aim-helm-rails-test-salt"
    config.active_storage.service = :test
    config.active_job.queue_adapter = ENV.fetch("QUEUE_ADAPTER", "test").to_sym
    config.solid_queue.connects_to = { database: { writing: :queue } }
    config.generators.orm :active_record
    config.paths["db/migrate"] << ActiveStorage::Engine.root.join("db/migrate")
    config.log_level = :warn

    initializer "test_app.aim_helm_rails", before: "aim_helm_rails.runtime" do
      AimHelmRails.host_class = "ChatIntegration"
    end
  end
end
