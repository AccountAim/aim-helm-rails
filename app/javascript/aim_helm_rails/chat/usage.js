// Usage rollups for a run: its own provider calls plus every subagent it spawned, priced
// server-side. Steps carry the agent that made the call so a row is always attributable.
export const collectSteps = (run, agent = null) =>
  [
    ...Object.values(run.usage || {}).map((step) => ({ ...step, agent })),
    ...Object.values(run.turns).flatMap((turn) =>
      Object.values(turn.tools).flatMap(({ child }) =>
        child ? Object.values(child.runs).flatMap((childRun) => collectSteps(childRun, child.name)) : [],
      ),
    ),
  ].sort((left, right) => left.order - right.order)

export const rollup = (steps, model = null) =>
  steps.reduce(
    (total, step) => ({
      model,
      calls: total.calls + 1,
      input: total.input + (step.input || 0),
      cached: total.cached + (step.cached || 0),
      output: total.output + (step.output || 0),
      cost: total.cost + (step.cost || 0),
    }),
    { model, calls: 0, input: 0, cached: 0, output: 0, cost: 0 },
  )

export const byModel = (steps) =>
  Object.entries(Object.groupBy(steps, ({ model }) => model)).map(([model, rows]) => rollup(rows, model))
