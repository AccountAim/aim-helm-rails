---
name: agent-acceptance
description: Validate AimHelmRails lifecycle scenarios and separate-worker execution. Use for durable-session changes, provider compatibility checks, and acceptance validation before a release.
---

# Agent Acceptance

Use the comprehensive scenario spec as the executable contract. Keep validation independent from
implementation work and report evidence without fixing failures unless the user asks.

## Workflow

1. Read this repository's `AGENTS.md`, `CONTRIBUTING.md`, and `spec/scenarios/README.md`.
2. Inspect current diffs affecting the engine, runtime dependency, scenarios, and this skill.
3. If this is the coordinating agent, delegate the run to one fresh subagent when delegation is
   authorized. Give it this skill path, validation mode, and current commit SHA only; do not include
   expected failures or prior conclusions. If the task was already delegated to you as the
   validator, execute it directly.
4. Run the selected mode from this repository's root.
5. Return the exact command, engine commit SHA, resolved runtime revision, pass/fail counts, failing example names, and the first
   actionable backtrace location for each failure. Separate harness failures from model-behavior
   failures. Do not change files during validation.

## Modes

- Deterministic: run `just scenarios`, then `just worker-smoke`. Use this by default.
  The first command owns lifecycle correctness inside transactional fixtures; the second proves
  job serialization and execution in a separate Solid Queue worker process.
- Live providers: run `just live-scenarios`. Run only when the user explicitly requests live
  validation and provider credentials are configured. Never print credentials.
- Browser: validate the chat in a consuming application after the deterministic contract passes,
  following that application's browser-testing instructions. Browser checks do not replace the
  scenario spec.

For a specific story, pass its filter directly, for example
`just scenarios --example "background subagent"`. Do not insert a standalone `--`; the
recipe forwards positional arguments to RSpec. Do not run the whole live matrix merely to reproduce
one provider failure.

## Subagent steering and approvals

Treat steering a subagent and approving one of its tools as separate lifecycle contracts. A root
approval, a child report arriving while the parent is parked, or permission to grant a gated tool
to a background child does not prove approval inside that child.

### Steering

The deterministic example `steers, resumes, and receives late reports from one background
specialist` is the minimum steering contract. It must prove all of the following through the public
facade and durable log:

- `AimHelmRails::Runtime.run(child, prompt, actor:, tenant:)` targets the child while its initial background turn is
  queued or running;
- the queued input is folded into the child's next provider request without changing child
  identity or widening its grant;
- the first child completion writes one terminal and one late report that wakes the parent;
- the same `AimHelmRails::Runtime.run` call starts another turn once the child is terminal, retaining prior
  transcript context;
- the second completion produces a second terminal and a second independently keyed parent report;
- parent and child normalized events remain aligned with their durable entries.

The live example `steers, continues, and receives two late reports from a live specialist` checks
that a real model follows the steered direction. Its structured marker is machine-checkable; prose
quality remains a human judgment.

### Approval inside a subagent

Inline subagents cannot park their synchronous caller, so they must reject approval-gated tools
before dispatch. Background subagents may receive gated tools, but an end-to-end deterministic
approval scenario must additionally prove:

1. the child requests the gated tool and reaches `awaiting_approval` on its own session;
2. the tool has not executed, no terminal or child report exists, and the parent is not woken;
3. `AimHelmRails::Runtime.decide(session: child, ..., verdict: :approve, actor:, tenant:)` records the decision and dispatches the
   child, not the parent;
4. the resumed worker reconstructs the same child turn and grant, executes the tool exactly once,
   reaches a terminal state, and delivers one durable report to the parent;
5. denial records a model-visible denied result without executing the tool, and duplicate decisions
   or wakes do not execute it or report it twice.

The deterministic example `parks and resumes approval-gated tools inside a background subagent` is
the required end-to-end contract. It covers one approved and one denied call in a single parked
batch, a duplicate decision, a redundant queued child wake, exact-once execution, one terminal child
report, and the completed parent's immediate durable report fold. Keep the lower-level inline
rejection/background-grant spec as a separate grant-boundary check.

## Interpretation

- Deterministic failures are runtime regressions or acceptance-spec defects; identify which from
  the durable entries and event assertions.
- Live structured facts and durable transitions are machine-checkable. Prose quality, specialist
  focus, and synthesis quality require a short human judgment note.
- Public scenarios do not close crash-transition coverage. Report component specs separately when
  the change touches append, lease, retry, approval, or report-delivery ordering.
- A skipped live group is expected unless live mode was requested. A skipped deterministic example
  is a validation failure.
- Report steering and subagent-tool approval independently; never use one as evidence for the
  other.

Stop after reporting. Ask before changing transaction strategy, queue adapters outside the example
scope, provider models, budgets, or live-service state.
