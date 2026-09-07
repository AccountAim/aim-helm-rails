import { computed, reactive, readonly } from "vue"

const runningRun = ({ message, userTimestamp, attachments = [], pending = false }) => ({
  attachments,
  failures: {},
  finishedAt: null,
  logOpen: true,
  logTouched: false,
  message,
  pending,
  status: "running",
  turns: {},
  usage: {},
  userTimestamp,
})

// The conversation as the event stream leaves it. Components read the readonly projection and call
// actions; only this closure writes. Accessors read back through their owner after creating, so a
// mutation never lands on a raw object the reactive proxy is not watching.
export const createChatStore = (sessionId) => {
  const state = reactive({ runs: {} })
  const childIndex = {}
  const subagentParents = {}
  let usageOrder = 0

  const runFor = (root, runId) => {
    if (root === state) bindPending(runId)
    root.runs[runId] ||= runningRun({})
    return root.runs[runId]
  }

  const turnFor = (run, turnId) => {
    run.turns[turnId] ||= { blocks: {}, completed: false, nextOrder: 0, thinking: {}, tools: {} }
    return run.turns[turnId]
  }

  const addBlock = (turn, key, attributes) => {
    turn.blocks[key] ||= { order: turn.nextOrder++ }
    return Object.assign(turn.blocks[key], attributes)
  }

  // A call's later events can carry a later turn than its start; the call id is its identity.
  const toolFor = (run, turnId, callId, attributes = {}) => {
    const owner = Object.values(run.turns).find((turn) => turn.tools[callId]) || turnFor(run, turnId)
    owner.tools[callId] ||= { call_id: callId, status: "started" }
    return Object.assign(owner.tools[callId], attributes)
  }

  const rootBusy = (root) => Object.values(root.runs).some((run) => run.status === "running")

  const runHasBusySubagent = (run) =>
    Object.values(run.turns).some((turn) => Object.values(turn.tools).some(({ child }) => child && rootBusy(child)))

  const seedRuns = (root, history) => {
    history.forEach(({ run_id, message, items, attachments, user_timestamp, assistant_timestamp }) => {
      root.runs[run_id] = runningRun({ attachments, message, userTimestamp: user_timestamp })

      const run = root.runs[run_id]
      run.finishedAt = assistant_timestamp
      run.logOpen = !assistant_timestamp
      run.status = assistant_timestamp ? "done" : "running"

      items.forEach((item) => seedItem(run, item))
    })
  }

  const seedItem = (run, item) => {
    const turn = turnFor(run, item.turn_id)

    if (item.type === "usage") {
      addUsage(run, item)
    } else if (item.type === "tool") {
      toolFor(run, item.turn_id, item.call_id, { ...item, status: item.status })
    } else if (item.type === "subagent") {
      attachSubagent(run, item.turn_id, item)
    } else if (item.type === "thinking") {
      turn.thinking[item.index] = { chunks: [item.content] }
    } else if (item.type === "text") {
      addBlock(turn, `text-${item.index}`, { content: item.content, index: item.index, type: "text" })
      turn.completed = true
    } else {
      addBlock(turn, `${item.type}-${item.id}`, item)
    }
  }

  const appendThinking = (turn, { delta, index, sequence }) => {
    turn.thinking[index] ||= { chunks: [] }
    turn.thinking[index].chunks[sequence] = delta
  }

  const appendMessage = (turn, { delta, index, sequence }) => {
    if (turn.completed) return

    const block = addBlock(turn, `text-${index}`, { index, type: "text" })
    block.chunks ||= []
    block.chunks[sequence] = delta
    block.content = block.chunks.filter((chunk) => chunk != null).join("")
  }

  const completeTurn = (turn, message) => {
    const finalKeys = new Set()

    message.content.forEach((block, index) => {
      if (block.type !== "text") return

      const key = `text-${index}`
      finalKeys.add(key)
      Object.assign(addBlock(turn, key, { index, type: "text" }), { chunks: [], content: block.text })
    })

    Object.entries(turn.blocks).forEach(([key, block]) => {
      if (block.type === "text" && !finalKeys.has(key)) delete turn.blocks[key]
    })
    turn.completed = true
  }

  const attachSubagent = (run, turnId, { call_id, name, run_id, runs = [], session_id, task }) => {
    const tool = toolFor(run, turnId, call_id)
    tool.child ||= { open: false, runs: {} }

    const child = tool.child
    Object.assign(child, { name, sessionId: session_id, task })
    childIndex[session_id] = child
    subagentParents[session_id] = run
    seedRuns(child, runs)

    if (run_id) child.runs[run_id] ||= runningRun({ message: task })
    if (!run.logTouched && rootBusy(child)) run.logOpen = true
  }

  // Keyed by turn so a live step and the same step seeded from history collapse into one, and
  // ordered by arrival because a live step has no durable id to sort on yet.
  const addUsage = (run, step) => {
    const key = step.turn_id || step.sequence
    const order = run.usage[key]?.order ?? ++usageOrder
    run.usage[key] = { ...step, order }
  }

  const finish = (run, status) => {
    run.finishedAt = new Date().toISOString()
    if (!run.logTouched) run.logOpen = runHasBusySubagent(run)
    run.status = status
  }

  const pendingEntries = () => Object.entries(state.runs).filter(([, run]) => run.pending)

  // One optimistic bubble at a time: the next submit is the same message until the run binds.
  const addPending = (message, attachments = []) => {
    if (pendingEntries().length) return

    state.runs[`pending-${crypto.randomUUID()}`] = runningRun({
      attachments,
      message,
      pending: true,
      userTimestamp: new Date().toISOString(),
    })
  }

  const bindPending = (runId) => {
    if (state.runs[runId]) return

    const entry = pendingEntries().at(0)
    if (!entry) return

    const [pendingId, run] = entry
    delete state.runs[pendingId]
    run.pending = false
    state.runs[runId] = run
  }

  const removePending = () => pendingEntries().forEach(([id]) => delete state.runs[id])

  const setLogOpen = (runId, open) => {
    const root = [state, ...Object.values(childIndex)].find(({ runs }) => runs[runId])
    const run = root.runs[runId]
    run.logTouched = true
    run.logOpen = open
  }

  const setSubagentOpen = (session_id, open) => {
    childIndex[session_id].open = open
  }

  const apply = (event) => {
    const root = event.sessionId === sessionId.value ? state : childIndex[event.sessionId]
    if (!root) return false

    const run = runFor(root, event.runId)
    const { name, payload, turnId } = event
    if (root !== state && name === "run.started") {
      const parent = subagentParents[event.sessionId]
      if (!parent.logTouched) parent.logOpen = true
    }

    switch (name) {
      case "turn.started":
        turnFor(run, turnId)
        break
      case "thinking.delta":
        appendThinking(turnFor(run, turnId), payload)
        break
      case "message.delta":
        appendMessage(turnFor(run, turnId), payload)
        break
      case "tool.started":
        toolFor(run, turnId, payload.call_id, { ...payload, status: "started" })
        break
      case "tool.completed":
        toolFor(run, turnId, payload.call_id, { ...payload, status: "done" })
        break
      case "tool.failed":
        toolFor(run, turnId, payload.call_id, { ...payload, status: "failed" })
        break
      case "tool.preview":
        toolFor(run, turnId, payload.call_id, { preview: payload.image })
        break
      case "subagent.spawned":
        attachSubagent(run, turnId, {
          call_id: payload.call_id,
          name: payload.name,
          run_id: payload.subagent_run_id,
          session_id: payload.subagent_session_id,
          task: payload.task,
        })
        break
      case "provider.failed":
        run.failures[`provider-${turnId}`] = payload
        break
      case "turn.completed":
        completeTurn(turnFor(run, turnId), payload.message)
        if (payload.usage) addUsage(run, { ...payload.usage, turn_id: turnId })
        break
      case "resource.render.inline":
        addBlock(turnFor(run, turnId), `resource-${payload.id}`, { type: "resource", ...payload })
        break
      case "run.completed":
        finish(run, "done")
        break
      case "run.stopped":
        finish(run, "stopped")
        break
      case "run.failed":
        if (!Object.keys(run.failures).length) run.failures[`run-${event.runId}`] = payload
        finish(run, "failed")
        break
    }

    return true
  }

  return {
    addPending,
    apply,
    bindPending,
    busy: computed(() => rootBusy(state)),
    hasPending: computed(() => pendingEntries().length > 0),
    removePending,
    seed: (history) => seedRuns(state, history),
    setLogOpen,
    setSubagentOpen,
    state: readonly(state),
  }
}
