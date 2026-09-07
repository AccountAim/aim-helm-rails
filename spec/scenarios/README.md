# Agent acceptance scenarios

[`acceptance_spec.rb`](acceptance_spec.rb) is the product-level contract for the `AimHelmRails::Runtime` facade,
Active Record store, jobs, approvals, subagents, and event projection. Deterministic examples use
`AimHelm::Providers::Fake`; examples tagged `:live` require configured providers.

From this repository:

```sh
# Deterministic lifecycle contract
just scenarios

# Serialization and execution in an isolated Solid Queue worker
just worker-smoke

# Real providers; requires credentials
just live-scenarios
```

The recipes run against the included Rails test app in isolated Docker services.

The worker smoke uses the isolated `agent_acceptance` queue, never calls a provider, and deletes the
records it creates. The recipe starts and stops its own worker process.

Live vision and worker examples default to `gpt-5.6-luna`; orchestration parents default to
`gpt-5.6-terra`. Override `AGENT_MODEL`, `AGENT_PARENT_MODEL`, or `AGENT_CHILD_MODEL` to exercise
other catalog models. The vision fixture is embedded so replay does not depend on an expiring URL.

Each scenario asserts normalized events, durable entries, and derived status. Steering a child,
approving a child's tool, root approval, and reporting to a parked parent are separate lifecycle
contracts.

To inspect a live failure, print the root and child session IDs and read the ordered log:

```ruby
session = AimHelmRails::Session.find("<session-id>")
AimHelm.session(session.id).entries.map(&:dump)
```
