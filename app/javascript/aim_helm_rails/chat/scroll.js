import { nextTick, ref, watch } from "vue"

const SETTLING_EVENTS = ["turn.started", "turn.completed", "run.completed", "run.failed", "run.stopped"]
const STREAMING_EVENTS = [
  "message.delta",
  "provider.failed",
  "subagent.spawned",
  "thinking.delta",
  "tool.completed",
  "tool.failed",
  "tool.started",
  "resource.render.inline",
]

// Following the transcript is a measurement, so every decision waits for Vue to render the event
// that changed it.
export const useScrollFollow = () => {
  const container = ref(null)
  const scrolledUp = ref(false)
  let stickTimer = null

  const distance = () => {
    const { scrollHeight, scrollTop, clientHeight } = container.value
    return scrollHeight - scrollTop - clientHeight
  }

  // A pin holds through late growth (charts sizing, frames loading) until the reader
  // intervenes — a smooth ride still animating reads as far from the bottom.
  let pinned = false

  const toBottom = () => {
    pinned = true
    container.value.scrollTo({ top: container.value.scrollHeight, behavior: "smooth" })
  }

  const unpin = () => (pinned = false)

  // The scrollbar shows under the pointer and while the transcript moves. Chromium repaints a
  // custom scrollbar on an attribute change but not on :hover alone, so hover sets it too.
  let scrollingTimer = null

  const reveal = () => (container.value.dataset.scrolling = "")
  const conceal = () => delete container.value?.dataset.scrolling

  const onScroll = () => {
    scrolledUp.value = distance() > 50
    reveal()
    clearTimeout(scrollingTimer)
    scrollingTimer = setTimeout(() => container.value?.matches(":hover") || conceal(), 800)
  }

  // A reader who scrolled up keeps their place; anyone near the bottom rides the stream down.
  const stick = () => {
    if (stickTimer) return

    stickTimer = setTimeout(() => {
      stickTimer = null
      if (distance() < 120) toBottom()
    }, 150)
  }

  const follow = async (name) => {
    await nextTick()
    if (SETTLING_EVENTS.includes(name)) toBottom()
    else if (STREAMING_EVENTS.includes(name)) stick()
  }

  // Tiles and chart canvases finish sizing after the event that inserted them; a held pin or
  // pre-growth nearness to the bottom rides that late growth down.
  let observer = null
  let observed = 0

  watch(container, (element) => {
    observer?.disconnect()
    if (!element) return

    element.addEventListener("wheel", unpin, { passive: true })
    element.addEventListener("touchmove", unpin, { passive: true })
    element.addEventListener("mouseenter", reveal)
    element.addEventListener("mouseleave", conceal)

    observed = 0
    observer = new ResizeObserver(([entry]) => {
      const grown = entry.contentRect.height - observed
      observed = entry.contentRect.height
      if (grown > 0 && (pinned || distance() - grown < 120)) toBottom()
    })

    observer.observe(element.firstElementChild)
  })

  const stop = () => {
    clearTimeout(stickTimer)
    observer?.disconnect()
  }

  return { container, follow, onScroll, scrolledUp, stop, toBottom }
}
