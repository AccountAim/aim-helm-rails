# AimHelmRails engine

This repository is the `aim-helm-rails` gem. Its standalone Rails test application lives in
`spec/dummy`. Use the Docker-backed recipes in this repository's `justfile`; see
`CONTRIBUTING.md` for setup. Do not commit or push without explicit permission.

Keep the implementation human-readable and follow AimHelm's established patterns: dry-rb value
objects, registries, stateless class methods, and `Success`/`Failure` at the runner boundary. Jobs
receive exceptions; monads do not cross the job boundary.

Each engine registers its Ruby controllers, jobs, models, and services under its own root namespace.
The custom root supplies the namespace; a generated namespace directory would add it a second time.
Place generated files directly in those directories while retaining their Ruby namespace:
`app/models/session.rb` defines `AimHelmRails::Session`. Helpers, views, and JavaScript keep
namespace directories for their separate lookup conventions.

Separate method definitions with one blank line when either is multiline; keep consecutive one-line
definitions together. Separate multiline control flow from neighboring statements. Group multiple
class methods in `class << self` when a class also has instance methods.

## Helmsmen and tools

`AimHelmRails::Helmsman` and `AimHelmRails::Tool` provide generic declarations and serialization.
Resolve host behavior through the configured integration; keep domain helmsmen and tools in the
consuming application.

- Helmsmen declare `model`, `reasoning`, `description` (required when granted as a subagent),
  `subagent Other, mode:`, and a one-entry-per-line `tools` array. Each grant has one author-chosen
  mode. `agent` assembles the AimHelm agent and is the permission-narrowing seam.
- Tool descriptions own tool-specific usage policy; a helmsman's `<tools>` section owns workflows
  across tools. A tool may return `AimHelm::Tool::Result` or bare content; `AimHelmRails::Tool.coerce`
  serializes hashes and arrays as JSON and passes strings through.
- Helmsman instructions follow `__END__` in the class file. Substantial prompts use semantic XML in
  this order when applicable: `<identity>`, `<data>`, domain sections, `<tools>`, `<autonomy>`,
  `<delegation>`, `<grounding>`, `<answer-format>`, `<stopping>`. Focused prompts may use plain prose.
- Omit empty sections and state each rule once. Keep tool-specific behavior out of helmsman prompts,
  use kebab-case for new tags, and reserve `always` and `never` for invariants. Prompt bodies use
  plain prose without Markdown headers or emphasis; backticks are fine for identifiers.

## AimHelm

- `aim-helm` has no Rails-family runtime dependency. Optional Active Record and Active Job
  adapters load conditionally from the same gem.
- Shared runtime wiring belongs in `lib/aim_helm_rails/helm_integration.rb`: models, jobs,
  providers, telemetry, and broadcasting. `lib/aim_helm_rails/engine.rb` contains Rails engine setup.
  Host policies, helmsmen, tools, and resource presentation belong in the consuming application.
- Experimental features staged for the gem live in `lib/aim_helm/features/` (gem-bound, Rails-free)
  with Rails adapters in `lib/aim_helm_rails/features/`; see its `README.md`.
- Use `Dry::Struct` for typed construction and owned data. Keep runtime stream state private and
  `Session::Record` payloads string-keyed so provider JSON round-trips without loss.
- AimHelm uses Zeitwerk. Public constants live at matching paths; namespace directories contain
  only their implementation family.
- Update model IDs, capabilities, context limits, and prices together in the `aim-helm` gem's
  `lib/aim_helm/models.yml`.
- Run the isolated gem suite and lint from its repository with `just spec` and `just rubocop`.
  Validate optional Rails adapters through the engine specs. Keep replay fixtures for provider wire
  formats; live specs require `AIM_HELM_LIVE=1` and explicit credentials.

## Validation

- For Agent or AimHelm lifecycle, provider, tool, approval, subagent, retry, budget, compaction,
  reminder, or event-broadcasting changes, read
  `skills/agent-acceptance/SKILL.md` completely and follow it after the user agrees on
  the code. Use deterministic scenarios by default; live modes require an explicit request.
- After changing engine controllers, views, or JavaScript, validate the rendered UI in a consuming
  application, following that application's browser-testing instructions.
- Scaffold models and migrations with Rails generators. Run `just rubocop` on changed Ruby files.
  Use the repository's Prettier configuration for JavaScript.
