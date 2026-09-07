Gem::Specification.new do
  it.name = "aim-helm-rails"
  it.version = "0.1.0"
  it.authors = ["gauravs"]
  it.summary = "Embeddable Rails chat and durable agent sessions"
  it.description = "Rails integration for the AimHelm agent runtime"
  it.license = "MIT"
  it.homepage = "https://github.com/AccountAim/aim-helm-rails"

  it.required_ruby_version = ">= 3.4.0"

  it.files = Dir["{app,config,db,docs,lib}/**/*"] + %w[README.md CONTRIBUTING.md LICENSE]
  it.require_paths = ["lib"]

  it.add_dependency "aim-helm"
  it.add_dependency "concurrent-ruby"
  it.add_dependency "image_processing"
  it.add_dependency "importmap-rails"
  # Rails 8.1's JSON decoder passes the options hash positionally.
  it.add_dependency "json", ">= 2.0", "< 3"
  it.add_dependency "lucide-rails"
  it.add_dependency "rails", ">= 8.1"
  it.add_dependency "ruby-vips", "~> 2.0"
  it.add_dependency "solid_queue"
  it.add_dependency "stimulus-rails"
  it.add_dependency "turbo-rails"

  it.metadata["rubygems_mfa_required"] = "true"
  it.metadata["source_code_uri"] = it.homepage
  it.metadata["bug_tracker_uri"] = "#{it.homepage}/issues"
  it.metadata["documentation_uri"] = "#{it.homepage}/blob/main/docs/integration.md"
end
