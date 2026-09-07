# Features

Experimental AimHelm features, developed here and moved to `aim-helm` once they settle. Each
feature is split across two directories so the move is a copy, not a rewrite:

- `lib/aim_helm/features/<name>/` is the feature: a port (adapter interface), the operations, and
  the `AimHelm::Tool`s built on them. It is copied verbatim into the gem's
  `lib/aim_helm/features/`.
- `lib/aim_helm_rails/features/<name>/` supplies Rails storage adapters and registration into
  the configured host tool registry. It stays in this engine.

## Rules for `lib/aim_helm/features`

- Depends only on Ruby, dry-rb, and `AimHelm`. Host dependencies go through the adapter interface.
- The port is duck-typed and documented on the feature class (`Workspace#read`, `#write`, …). The
  host supplies it as an object or a `context -> adapter` resolver, so identity and scoping never
  appear in model-visible tool arguments.
- Tool names, descriptions, and schemas are generated from `name:`/`purpose:` so a host can mount
  the same feature more than once (`memory`, `knowledge_base`).
- Specs live in `spec/aim_helm/features/` and use in-memory fakes for the port. They move with the
  code.

## Rules for `lib/aim_helm_rails/features`

- One adapter per storage backend, implementing the port over app models.
- `register` adds tools to the supplied registry; grant helpers (`knowledge_base_tools(access:)`) own
  which operations a helmsman receives.
- An adapter may later graduate to the gem's optional Active Record adapters, but only once it owns
  its table instead of reaching into app models.

## Moving a feature

1. Copy `lib/aim_helm/features/<name>*` and its specs into the gem; run the gem's `just spec` and
   `just rubocop`.
2. Update the dependency here with `bundle update aim-helm` and delete the staging copy.
3. Keep the Rails adapter under `lib/aim_helm_rails/features/<name>`.

## Current

- `workspace` — documents behind an adapter with list/read/write/edit/search tools and
  revision-checked edits. Host adapter: `Adapters::ActiveRecord` over `WorkspaceDocument`.
