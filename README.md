# AimHelmRails

`aim-helm-rails` adds embeddable chat, uploads, durable sessions, background execution,
approvals, and workspace storage to Rails applications using
[`aim-helm`](https://github.com/AccountAim/aim-helm).

The Ruby namespace is `AimHelmRails`. Your app owns authentication, authorization, actors,
tenants, helmsmen, tools, chat navigation, and rendered resources.

The engine is under active development. Its host integration API and migrations may change before
the first stable release.

## Integration

### 1. Install the gems

Use Ruby 3.4+ and Rails 8.1+. Add these to your application's Gemfile and run `bundle install`:

```ruby
gem "aim-helm", github: "AccountAim/aim-helm", require: false
gem "aim-helm-rails", github: "AccountAim/aim-helm-rails"
```

`aim-helm` is already a runtime dependency in this engine's gemspec. Its Gemfile entry selects
the GitHub source, since gemspecs cannot specify Git URLs. Once both gems are available from your
configured gem server, only the `aim-helm-rails` entry is needed.

Loading the engine also loads its required Solid Queue, importmap, Turbo, Stimulus, and Lucide integrations.
Its gemspec owns attachment processing (`image_processing` and `ruby-vips`); Active Storage loads
the selected image backend. Your app only needs separate entries for libraries it uses directly
or sources/versions it wants to select.

### 2. Supply the host integration

Configure reloadable class names in `config/initializers/aim_helm_rails.rb`:

```ruby
AimHelmRails.host_class = "ChatIntegration"
AimHelmRails.controller_class = "ApplicationController"
```

The controller must authenticate requests and expose `current_actor` and `current_tenant`.
Both return persisted, GlobalID-capable models. A single-tenant app still supplies a tenant.
Verify the actor's membership in that tenant in your authorization policy.

Implement `ChatIntegration` using the [host contract](docs/integration.md#host-wiring). It supplies
authorized session queries, first-message session creation, upload authorization, a helmsman/tool
registry, and resource URLs. These policies are application-specific; the engine enforces tenant
scope as well. Define your helmsmen and tools as subclasses of `AimHelmRails::Helmsman` and
`AimHelmRails::Tool`.

### 3. Mount the routes

In `config/routes.rb`:

```ruby
mount AimHelmRails::Engine => "/helm", as: :aim_helm_rails
```

The prefix is your choice; the `aim_helm_rails` alias is required. The engine serves message and
upload endpoints. Your app serves the pages that contain chats and the resource frames returned
by tools.

### 4. Prepare storage and migrate

Configure Active Storage, Active Record Encryption keys, and Solid Queue in the host. Install their
tables if the app does not already have them. Use libvips for image variants and Poppler for PDF
previews.

Set Rails' generator `primary_key_type` to match the host's Active Storage `record_id` type before
running migrations. The engine's attachment keys follow that setting; actor and tenant GIDs work
with either UUID or integer host IDs. Chat sessions always use UUIDv7.

```sh
bin/rails db:migrate
```

Engine migrations are automatically included in the host's migration paths. Run the same command
after gem upgrades; do not copy or edit released engine migrations.

### 5. Embed a chat

Authorize the page in your controller and include the chat helper:

```ruby
helper AimHelmRails::ChatsHelper
```

Pass an authorized existing session, or build an unsaved one for a new chat:

```ruby
@chat = AimHelmRails::Session.new(actor: current_actor, tenant: current_tenant,
                                  helmsman: "analyst", interactive: true)
```

Render it inside an element with a height:

```erb
<div class="h-full min-h-0">
  <%= render @chat %>
</div>
```

Uploads are staged without creating a session. Sending the first message persists the chat and
claims its uploads together. Listen for `agent:chat-created` if your page should navigate to the
new chat; the event's `detail.path` is supplied by your integration.

### 6. Load the UI assets

The host uses importmap, Turbo, Stimulus, and Tailwind. Engine importmap pins and JavaScript asset
paths register automatically; keep the normal Stimulus controller loader in the host. Include
`csrf_meta_tags`, `javascript_importmap_tags`, your stylesheet, and `yield :head` in the layout.

Add the engine's `app/views` and `app/javascript` directories to Tailwind's source inputs. Find the
installed path with `bundle show aim-helm-rails`.
Supply your theme tokens and chat styles; see the [asset contract](docs/integration.md#chat-component-and-assets).
The importmap currently uses CDN-hosted Vue, Markdown, sanitization, PDF, and spreadsheet libraries;
allow their origins in your CSP or vendor those pins.

### 7. Run workers and enable live updates

Use Solid Queue workers that consume `agent`, `agent_subagents`, and Active Storage's queues.
Configure an Action Cable adapter shared by web and worker processes, such as Solid Cable.
Add the [recurring recovery and upload-cleanup jobs](docs/integration.md#host-wiring), then start
your workers. Set `OPENAI_API_KEY` and/or `ANTHROPIC_API_KEY` for the providers your helmsmen use.

Verify a first message, an upload, a tool-rendered resource, and a page reload through your app.
Resource endpoints must authorize each GID and return the requested Turbo frame.

## Development

The repository includes a minimal Rails test application in `spec/dummy`. Docker Compose runs
PostgreSQL and the test app independently of any consuming application. Install Docker Compose
and [Just](https://just.systems), then run:

```sh
just spec
just rubocop
just scenarios
just worker-smoke
```

The recipes build their image and prepare their test databases. The worker smoke starts and stops
its own Solid Queue process. Default tests use fake providers and need no API keys.

Run `just package` to check gem packaging and `just stop` to stop the test services.
See [CONTRIBUTING.md](CONTRIBUTING.md) for focused checks and optional live-provider tests.

See [the integration reference](docs/integration.md) for authorization, uploads, resource slots,
execution, and workspaces.

## License

Available under the [MIT license](LICENSE).
