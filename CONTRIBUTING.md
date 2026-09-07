# Contributing

AimHelmRails is a Rails engine built on the [AimHelm runtime](https://github.com/AccountAim/aim-helm).
Keep application policies, actors, tenants, helmsmen, and domain tools behind the
[host integration](docs/integration.md). Use generic examples and synthetic fixtures.

## Setup

Clone this repository and install Docker Compose and [Just](https://just.systems).
No sibling checkouts, private gems, or provider credentials are needed.

```sh
just spec
just rubocop
just worker-smoke
just package
```

The recipes build a development image and prepare PostgreSQL test databases. The Rails app in
`spec/dummy` supplies only test identities and infrastructure. The suite also checks engine
migrations on SQLite and PostgreSQL with integer and UUID host keys.

For a focused change:

```sh
just spec spec/models/aim_helm_rails/attachment_spec.rb
just rubocop app/models/attachment.rb
just scenarios --example "background subagent"
```

Stop the test services with `just stop`. These services do not connect to a consuming app's
databases or workers. To run without Docker, install Ruby 3.4+, PostgreSQL 18, libvips, and Poppler,
then run `bundle install`, `RAILS_ENV=test bundle exec rake db:prepare`, and `bundle exec rspec`.
Set `DB_HOST`, `DB_USER`, and `DB_PASSWORD` for your local PostgreSQL instance.

## Validation

Use existing behavior specs and add focused regression coverage. For lifecycle changes, run the
[acceptance scenarios](spec/scenarios/README.md) and the separate-worker smoke. UI changes also
need validation in a consuming application: exercise the changed controls, check the browser
console, and inspect the rendered result.

Live-provider checks are opt-in and can incur API charges. Export only the credentials you intend
to use, then run `just live-scenarios`. Default checks use fake providers; they never need keys.
Do not commit credentials, real transcripts, customer data, or files from a private application.

## Changes

Keep changes focused, code readable, and comments limited to non-obvious behavior. Update the
integration reference when a public contract changes. Published migrations are immutable; add
a migration for schema changes after release.

Open a pull request describing the behavior, validation performed, and any checks not run.
Commits and pushes by coding agents require the contributor's explicit approval.
