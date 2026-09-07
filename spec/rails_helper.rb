ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "rspec/rails"
require_relative "support/identities"
require_relative "support/host"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.filter_run_excluding worker: true
  config.filter_rails_from_backtrace!
  config.mock_with(:rspec) { it.verify_partial_doubles = true }
end
