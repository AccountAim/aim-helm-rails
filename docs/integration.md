# Host integration reference

`aim-helm-rails` provides an embeddable Rails chat and durable sessions on `aim-helm`.
The host supplies actors, tenants, authorization, helmsmen, tools, and resource rendering. Sessions,
uploads, transcripts, execution, approvals, workspace storage, and recovery belong to the engine.

Ruby controllers, jobs, models, and services use `AimHelmRails` as their autoload root namespace:
`app/models/session.rb` defines `AimHelmRails::Session`. Helpers, views, and JavaScript retain
namespace directories for Rails helper/template discovery and asset lookup.

## Host wiring

Configure reloadable class names in an initializer:

```ruby
AimHelmRails.host_class = "ChatIntegration"
AimHelmRails.controller_class = "ChatController"
```

`controller_class` defaults to `::ApplicationController`. The controller must authenticate requests
and provide `current_actor` and `current_tenant`, both returning persisted GlobalID-capable objects.
The engine derives their GIDs on the server; browser identity parameters are ignored.

The integration implements these class methods:

| Method | Contract |
| --- | --- |
| `tools` | Registry implementing `resolve`, `identifiers`, and `register`; normally a subclass of `AimHelmRails::Tool`. |
| `helmsman(name)` | Helmsman definition for execution, exposing `agent`. |
| `interactive_helmsman(name)` | Validate a browser-selected helmsman and expose `helmsman_name`. |
| `interactive_helmsmen_for(chat)` | Allowed helmsman definitions for the composer. |
| `sessions(actor:, tenant:)` | Authorized interactive-session relation; the engine also applies the tenant scope. |
| `open_chat(actor:, tenant:, id:, helmsman:, context:)` | Persist an interactive session. `context` is an optional opaque host reference. Called inside the first-message transaction. |
| `authorize!(record, actor:, tenant:, action:)` | Raise when access to a persisted record is denied. Engine calls use `read` and `update`. |
| `authorize_upload!(actor:, tenant:)` | Authorize creating staged uploads in the supplied tenant. |
| `session_path(session)` | Host navigation destination announced when a chat is created. |
| `context_pane(session)` | Initial context `{ src:, title: }`, or `{}`. |
| `resource_path(gid, frame:)` | Host URL returning the supplied Turbo frame ID. Resolve and authorize the GID in that endpoint. |

Authorization is host policy, including sharing. Ownership does not imply private-chat policy.
Session and attachment lookups enforce the supplied tenant independently. The host verifies the
actor's tenant membership and authorizes the page rendering the chat: the component emits its
signed Turbo stream subscription. Hosts query and destroy ordinary engine models directly and
authorize those operations themselves. A host can reuse `authorize!` with additional actions such
as `destroy`; those actions belong to its own policy. Add host associations through a concern
included from `config.to_prepare`.

```ruby
mount AimHelmRails::Engine => "/helm", as: :aim_helm_rails
```

The `aim_helm_rails` mount alias is required: engine views use that route proxy. The URL prefix
(`/helm` above) is host-defined.

`AimHelmRails::AdvanceSessionJob` defers enqueueing until all surrounding transactions commit;
a rollback discards the enqueue. This applies when Solid Queue uses a separate database too.

The engine loads application and engine routes at boot in every process, before concurrent tools
or broadcasts generate URLs. Development route reloading remains enabled.

Solid Queue workers must consume `agent`, `agent_subagents`, and the Active Storage job queues
(`default` with standard Rails configuration). Configure recurring jobs in deployed environments:

```yaml
production:
  sweep_stalled_agent_sessions:
    class: AimHelmRails::SweepStalledSessionsJob
    schedule: every minute
  purge_staged_agent_attachments:
    class: AimHelmRails::PurgeStagedAttachmentsJob
    schedule: every hour
```

The gem declares Rails 8.1+, Solid Queue, Active Storage through Rails, `image_processing`,
`ruby-vips`, importmap, Turbo, Stimulus, Lucide, and concurrent-ruby dependencies. The entrypoint
loads its Rails integrations; Active Storage loads the image backend. Configure Active Storage and install libvips
for image variants and Poppler for PDF previews. XLSX viewing uses the bundled browser controller.
Screenshot-browser infrastructure belongs to host tools.

Dependency declarations follow the code that uses them:

| Layer | Dependencies |
| --- | --- |
| `aim-helm` | dry-rb, concurrent-ruby, Faraday, its persistent HTTP adapter, and Zeitwerk |
| `aim-helm-rails` | AimHelm, Rails, Solid Queue, importmap, Turbo, Stimulus, Lucide, concurrent-ruby, and attachment processing |
| Host tools | Domain libraries and any screenshot or external-service clients they use |
| Host application | Database adapter, asset pipeline, theme, authentication, and configured storage/queue infrastructure |

Host code using a shared dependency still declares it directly. Domain renderers and their
dependencies belong to the host. Git and path
source selections remain in the consuming application's Gemfile; Bundler does not read a dependency
gem's Gemfile. See [RubyGems' dependency guidance](https://guides.rubygems.org/gemfile-and-gemspec/).

Engine migrations are added to host migration paths. After upgrading the gem, run the host's
`db:migrate`; Rails records applied versions in the host database. Published migrations are immutable.

Attachments, allow rules, and workspace documents use Rails' configured `primary_key_type`, falling
back to the adapter's standard primary key. Configure this before installation, consistently with
the host's existing Active Storage `record_id` column. Sessions always use UUIDv7, stored as native
UUIDs on PostgreSQL and strings on SQLite; session entries use integer keys. Session foreign keys
match the session primary key independently of other tables. Actor and tenant GIDs support either
host key type.

The `agent_*` table prefix is independent of the Ruby namespace. Existing installations need their
migration histories and persisted GIDs reconciled before adopting these migrations.

## Chat component and assets

Controllers that render the chat declare its helper:

```ruby
helper AimHelmRails::ChatsHelper
```

```erb
<%= render chat, draft: nil, autosubmit: false, context: nil, pane: {},
      examples: [{ prompt: "Summarize recent activity" }],
      empty_state: render("chats/empty_state") %>
```

Only the chat record is required. Suggested prompts default to none; the default empty state uses Lucide.
The engine uses native controls and Vue. Hosts own the surrounding layout
and everything inside a resource slot. Shared helpers use the `aim_helm_rails_` prefix.

JavaScript and importmap pins ship in the engine and register with the host asset pipeline. The
host compiles Tailwind classes. Add the installed engine's view and JavaScript directories to the
host's Tailwind entrypoint. Print the two source directives using the current bundle:

```sh
bundle exec ruby -e 'root = Gem::Specification.find_by_name("aim-helm-rails").full_gem_path; %w[app/views app/javascript].each { puts %(@source "#{root}/#{it}";) }'
```

Regenerate these paths when the installed gem location changes. Use Tailwind 4
with theme colors for `background`, `foreground`, `card`, `primary`, `primary-foreground`, `muted`,
`muted-foreground`, `accent`, `accent-foreground`, `border`, `destructive`, and `brand-secondary`.
These are CSS theme tokens; they do not require a component library. For example:

```css
@theme {
  --color-background: white;
  --color-foreground: #17212b;
  --color-card: white;
  --color-primary: #065f46;
  --color-primary-foreground: white;
  --color-muted: #f3f4f6;
  --color-muted-foreground: #6b7280;
  --color-accent: #e5e7eb;
  --color-accent-foreground: #17212b;
  --color-border: #d1d5db;
  --color-destructive: #b91c1c;
  --color-brand-secondary: #64748b;
}

[v-cloak] { display: none; }
```

Style rendered assistant Markdown under `.markdown` with your application's typography rules.
The host owns stylesheet compilation and typography. Verify a production asset build when
integrating the engine.

## Execution and identities

```ruby
chat = AimHelmRails::Session.create!(actor:, tenant:, helmsman: "analyst", interactive: true)
AimHelmRails::Runtime.run(chat, "Summarize recent activity.", actor:, tenant:)
AimHelmRails::Runtime.read(session: chat, actor:, tenant:)
AimHelmRails::Runtime.reply(session: chat, actor:, tenant:)
AimHelmRails::Runtime.stop(session: chat, actor:, tenant:)
```

Each turn rebuilds its helmsman and retains the last run's model and reasoning settings. Workers and
subagents restore an `ExecutionContext` containing the persisted execution actor and tenant. In a
AimHelm tool context, `context.app` is that execution context; it does not consult the actor's
currently selected organization. A collaborator can start a later turn, but must wait for the
active actor's run to finish before sending input under a different grant.

Concrete tools inherit `AimHelmRails::Tool`; helmsmen inherit `AimHelmRails::Helmsman`. Durable
records contain registered tool identifiers, resolved by workers before execution.
Tools expose `execution`, `actor`, and `tenant` readers for that persisted execution context.
`AimHelmRails::Runtime.decide(session:, call_id:, verdict:, actor:, tenant:, always_allow:)`
records approval decisions. Remembered approvals belong to the deciding actor within the tenant.

## Uploads

Uploads create staged attachments with `actor_gid` and `tenant_gid`, without creating a session.
The first message creates its session and claims uploads atomically. Only unclaimed, unexpired
uploads belonging to that actor and tenant can be claimed. Later uploads follow the same flow;
message input cannot move an already-claimed file to another chat.

Downloads and thumbnails use engine URLs and invoke host authorization. Before send, access follows
the uploader; afterward, the host can authorize through the session. Transcript resolution stays
within the originating chat, including its subagents. Staging expires after one day; recurring
cleanup destroys abandoned records. Active Storage purges their blobs. Session destruction destroys
its attachments. Files promoted into long-lived host resources need host-owned storage/lifecycle.

Attachment viewers use those same endpoints. Thumbnails accept `size: "small"` (320 pixels,
the default) or `size: "large"` (1200 pixels). The attachment partial accepts `url_options:` for
host-supplied request credentials, such as a short-lived, file-scoped preview token. The configured
host controller must authenticate those credentials and provide the actor and tenant; every file
request still invokes host authorization.

## Resource slots

A rendering tool persists a domain-neutral reference:

```ruby
resource = { gid: record.to_gid_param, title: "Report", placement: "inline" }
broadcast(:"resource.render.inline", **resource)
AimHelm::Tool::Result.success(content: "Displayed it.", metadata: { resource: })
```

Use `aside` to pin the resource. The engine derives frame IDs and asks the host for a URL. It never
resolves resource GIDs or selects their partials. The host returns the requested frame, including
an unavailable state for deleted/inaccessible resources. Repeated aside renders reload the frame;
saved results reconstruct the same presentation on page reload. Screenshot previews remain normal
image tool results, separate from lazy resource rendering.

## Workspaces

Operations are scoped by tenant, optional actor, kind, and key. A nil actor shares documents within
the tenant; an actor gives personal storage within the tenant.

```ruby
memory = AimHelmRails::Features::Workspace::Adapters::ActiveRecord
  .new(kind: :memory, actor:, tenant:)
knowledge = AimHelmRails::Features::Workspace::Adapters::ActiveRecord
  .new(kind: :knowledge_base, tenant:)

memory.write("profile.md", "Prefers concise reports.")
knowledge.read("products/widgets.md")
```

The Rails-free `AimHelm::Features::Workspace` wraps an adapter to provide generated list, read,
write, edit, and search tools. Conditional writes reject stale revisions without replacing newer
documents. Wiki tools, navigation, and rendering belong to the host.

## Validation

From this repository:

```sh
just spec
just scenarios
just worker-smoke
```

The development recipes use the included `spec/dummy` Rails app. Scenarios use a test integration
and generic runtime calls, independently of a host helmsman catalog. The separate-worker smoke owns
its worker process and temporary records. See [the contributor guide](../CONTRIBUTING.md).
