import { createApp, provide, ref } from "vue"
import { createChatStore } from "aim_helm_rails/chat/store"
import { useAttachments } from "aim_helm_rails/chat/attachments"
import { useComposer } from "aim_helm_rails/chat/composer"
import { useContextPane } from "aim_helm_rails/chat/context"
import { useScrollFollow } from "aim_helm_rails/chat/scroll"
import { useChatTransport } from "aim_helm_rails/chat/transport"
import { marked } from "marked"
import DOMPurify from "dompurify"
import { byModel, collectSteps, rollup } from "aim_helm_rails/chat/usage"

marked.setOptions({ gfm: true })

const time = (value) => new Date(value).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
const tokens = (value) => (value || 0).toLocaleString()
const money = (value) => `$${(value || 0).toFixed(4)}`
const plural = (count, noun) => `${count} ${noun}${count === 1 ? "" : "s"}`

// Model output is untrusted: sanitize before it reaches the one v-html boundary. Links open away
// from the chat, and a malformed chunk mid-stream falls back to its own text.
const markdown = (text) => {
  try {
    const template = document.createElement("template")
    template.innerHTML = DOMPurify.sanitize(marked.parse(text))
    template.content.querySelectorAll("a[href]").forEach((link) => {
      link.target = "_blank"
      link.rel = "noopener noreferrer"
    })
    return template.innerHTML
  } catch {
    return null
  }
}

const runActions = (run) =>
  Object.values(run.turns).reduce((total, turn) => total + Object.keys(turn.tools).length, 0) +
  Object.keys(run.failures).length

const taskText = (task) =>
  typeof task === "string"
    ? task
    : task
        .map((block) => block.text)
        .filter(Boolean)
        .join("")

const LogRow = {
  props: { entry: Object, status: String },
  computed: {
    label() {
      const { title, name, reason } = this.entry
      return title || name?.replaceAll("_", " ") || reason?.replaceAll("_", " ") || "Run failed"
    },
    detail() {
      const { arguments: args, description, error } = this.entry
      const json = args && Object.keys(args).length ? JSON.stringify(args) : null
      // A failed call still shows what it tried; its error waits in the hover card.
      return description || json || error
    },
    // One argument per block, strings printed as they are so code and SQL keep their lines.
    pretty() {
      const args = this.entry.arguments
      if (!args || !Object.keys(args).length) return null
      return Object.entries(args)
        .map(([key, value]) => `${key}: ${typeof value === "string" ? value : JSON.stringify(value, null, 2)}`)
        .join("\n\n")
    },
  },
  template: "#agent-log-row-template",
}

const Usage = {
  props: { spend: Array },
  computed: {
    total() {
      return rollup(this.spend)
    },
    rows() {
      const last = this.spend.at(-1)
      return [
        { label: ["last turn", last.agent, last.model].filter(Boolean).join(" · "), row: last, calls: "" },
        ...byModel(this.spend).map((row) => ({ label: row.model, row, calls: row.calls, edge: true })),
        { label: "total", row: this.total, calls: this.total.calls, edge: true, strong: true },
      ]
    },
  },
  methods: { tokens, money },
  template: "#agent-usage-template",
}

// Collapsed by default: a subagent's work is its own disclosure inside the parent's log, so the
// parent stays scannable and every row is attributable to the agent that ran it.
const Subagent = {
  props: { child: Object },
  inject: ["store"],
  computed: {
    runs() {
      return Object.values(this.child.runs)
    },
    label() {
      const actions = this.runs.reduce((total, run) => total + runActions(run), 0)
      const working = this.runs.some((run) => run.status === "running") ? "working…" : null
      return [this.child.name, actions ? plural(actions, "action") : working].filter(Boolean).join(" · ")
    },
    task() {
      return taskText(this.child.task)
    },
  },
  methods: {
    toggle(event) {
      event.preventDefault()
      this.store.setSubagentOpen(this.child.sessionId, !this.child.open)
    },
  },
  template: "#agent-subagent-template",
}

const Log = {
  props: { run: Object, runId: String, nested: Boolean, spend: Array },
  inject: ["store"],
  computed: {
    tools() {
      return Object.entries(this.run.turns).flatMap(([turnId, turn]) =>
        Object.values(turn.tools).map((tool) => ({ tool, turnId })),
      )
    },
    failures() {
      return Object.values(this.run.failures)
    },
    thinking() {
      return Object.values(this.run.turns)
        .flatMap((turn) => Object.values(turn.thinking))
        .map(({ chunks }) =>
          chunks
            .filter((chunk) => chunk != null)
            .join("")
            .trim(),
        )
        .filter(Boolean)
        .join("\n\n")
    },
    // A running turn has nothing of its own to bill yet, and the chat's earlier spend beside a
    // zero-action run reads as though the answer already cost that much.
    settled() {
      return this.run.status !== "running"
    },
    summary() {
      const total = rollup(this.spend)
      const count = this.tools.length + this.failures.length
      const parts = []
      if (this.run.finishedAt) parts.push(time(this.run.finishedAt))
      if (count) parts.push(plural(count, "action"))
      if (this.settled && total.calls) parts.push(money(total.cost))
      if (!parts.length && this.thinking) parts.push("Thinking…")
      return parts.join(" · ")
    },
  },
  methods: {
    // Once the reader opens or closes a log, the run keeps that through its own updates.
    toggle(event) {
      event.preventDefault()
      this.store.setLogOpen(this.runId, !this.run.logOpen)
    },
    // Rendering keeps scrollTop, so a log that was following the stream needs re-pinning; one the
    // reader scrolled up in stays put.
    pin() {
      const body = this.$refs.body
      if (body && this.following) body.scrollTop = body.scrollHeight
    },
  },
  data() {
    return { following: true }
  },
  beforeUpdate() {
    const body = this.$refs.body
    this.following = !body || body.scrollHeight - body.scrollTop - body.clientHeight < 8
  },
  mounted() {
    this.pin()
  },
  updated() {
    this.pin()
  },
  template: "#agent-log-template",
}

// Its own component so a completed block's Markdown is parsed once and cached, rather than
// reparsed every time the turn it lives in updates.
const TextBlock = {
  props: { block: Object },
  computed: {
    html() {
      return markdown(this.block.content)
    },
  },
  template: "#agent-text-block-template",
}

const AttachmentQueue = {
  props: { items: Array },
  emits: ["discard", "retry"],
  template: "#agent-attachment-queue-template",
}

const Turn = {
  props: { turn: Object },
  computed: {
    blocks() {
      return Object.values(this.turn.blocks).sort((left, right) => left.order - right.order)
    },
  },
  template: "#agent-turn-template",
}

const Run = {
  props: { run: Object, runId: String, nested: Boolean, spend: Array },
  computed: {
    stamp() {
      return time(this.run.userTimestamp)
    },
  },
  template: "#agent-run-template",
}

// Usage accrues across the conversation, so each run's log reports the chat's spend through that
// point rather than the run's slice of it.
const Transcript = {
  inject: ["store"],
  computed: {
    runs() {
      let spend = []

      return Object.entries(this.store.state.runs).map(([runId, run]) => {
        spend = spend.concat(collectSteps(run))
        return { runId, run, spend }
      })
    },
  },
  template: "#agent-transcript-template",
}

// Vue owns the chat page itself: the server-rendered markup inside the mount element is this
// component's template, so the page paints as Rails HTML and stays reactive from the mount on.
const ChatRoot = ({
  autosubmit,
  context,
  draft,
  events,
  helmsman: chosen,
  helmsmen,
  pane: pinned,
  path,
  runs,
  session,
  uploadPath,
}) => ({
  setup() {
    const store = createChatStore(session)
    const pane = useContextPane(pinned)
    const scroll = useScrollFollow()
    store.seed(runs)
    provide("store", store)

    // The aside holds a resource the run pins, not transcript state.
    const receive = (event) => {
      if (event.name === "resource.render.aside") return pane.open(event.payload)
      if (store.apply(event)) scroll.follow(event.name)
    }

    const helmsman = ref(helmsmen.find((option) => option.name === chosen) || helmsmen[0])
    // A chat keeps the helmsman it has; until then the first message picks one.
    const helmsmanFixed = ref(Boolean(chosen))
    const pin = (payload) => pane.open(payload, "auto")
    const transport = useChatTransport({ context, events, helmsman, path, pin, receive, session, store })
    const attachments = useAttachments(uploadPath)
    const send = async (...args) => {
      const sent = await transport.send(...args)
      if (sent) helmsmanFixed.value = true
      return sent
    }
    const composer = useComposer({ attachments, draft, send })

    // Refs unwrap in the template only at the top level of what setup returns.
    return {
      ...composer,
      ...scroll,
      attachments: attachments.attachments,
      discardAttachment: attachments.discard,
      retryAttachment: attachments.retry,
      busy: store.busy,
      contextFold: pane.fold,
      contextRevision: pane.revision,
      contextSrc: pane.src,
      contextTitle: pane.title,
      helmsman,
      helmsmanFixed,
      helmsmen,
      sessionId: session,
    }
  },
  mounted() {
    this.toBottom()
    if (autosubmit) this.submit()
  },
  unmounted() {
    this.stop()
  },
})

export const mountChat = (options) => {
  const app = createApp(ChatRoot({ ...options, session: ref(options.sessionId) }))
  app.config.compilerOptions.isCustomElement = (tag) => tag === "turbo-frame"
  Object.entries({ AttachmentQueue, Log, LogRow, Run, Subagent, TextBlock, Transcript, Turn, Usage }).forEach(
    ([name, component]) => {
      app.component(name, component)
    },
  )
  app.mount(options.root)

  return { unmount: () => app.unmount() }
}
