engine-directory := source_directory()
compose := "docker compose --project-directory " + quote(engine-directory)

export COMPOSE_PROGRESS := "quiet"

# Build the standalone development image.
@build:
    {{ compose }} build

# Create and migrate the isolated test databases.
@prepare:
    {{ compose }} run --rm test bundle exec rake db:prepare

# Run the engine specs against the included Rails test app.
[positional-arguments]
@spec *args: build prepare
    {{ compose }} run --rm test bundle exec rspec "$@"

# Lint the engine and its test app.
[positional-arguments]
@rubocop *args: build
    {{ compose }} run --rm --no-deps test bundle exec rubocop "$@"

# Run deterministic lifecycle scenarios.
[positional-arguments]
@scenarios *args: build prepare
    {{ compose }} run --rm test bundle exec rspec spec/scenarios/acceptance_spec.rb --tag ~live "$@"

# Real-provider checks explicitly forward credentials from the caller's environment.
[positional-arguments]
@live-scenarios *args: build prepare
    {{ compose }} run --rm -e AIM_HELM_LIVE=1 -e OPENAI_API_KEY -e ANTHROPIC_API_KEY \
      -e AGENT_MODEL -e AGENT_PARENT_MODEL -e AGENT_CHILD_MODEL test \
      bundle exec rspec spec/scenarios/acceptance_spec.rb --tag live "$@"

# Exercise job serialization in a separate Solid Queue process.
@worker-smoke: build prepare
    #!/usr/bin/env bash
    set -euo pipefail
    worker_id="$({{ compose }} run --rm --no-deps -d -e QUEUE_ADAPTER=solid_queue test \
      bundle exec ruby -r ./spec/dummy/config/environment -r solid_queue/cli \
      -e 'SolidQueue::Cli.start(ARGV)' -- \
      --config-file=/aim-helm-rails/spec/scenarios/queue.yml --skip-recurring)"
    cleanup() { docker stop "$worker_id" >/dev/null 2>&1 || true; }
    trap cleanup EXIT
    {{ compose }} run --rm --no-deps -e QUEUE_ADAPTER=solid_queue test \
      bundle exec ruby -r ./spec/dummy/config/environment spec/scenarios/worker_smoke.rb

# Validate the distributable gem archive.
@package: build
    {{ compose }} run --rm --no-deps test gem build aim-helm-rails.gemspec --output /tmp/aim-helm-rails.gem

# Stop this repository's test services.
@stop:
    {{ compose }} down
