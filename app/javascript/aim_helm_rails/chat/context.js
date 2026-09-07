import { ref } from "vue"

// fold: `auto` opens where the pane splits the chat and hides where it would cover it (the
// stylesheet decides); pins and clicks set `open`/`closed`.
export const useContextPane = (pinned) => {
  const src = ref(pinned.src || null)
  const title = ref(pinned.title || null)
  const revision = ref(0)
  const fold = ref("auto")

  const open = (pin, state = "open") => {
    src.value = pin.src
    title.value = pin.title
    fold.value = state
    revision.value++
  }

  return { fold, open, revision, src, title }
}
