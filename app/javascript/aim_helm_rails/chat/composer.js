import { nextTick, onMounted, onUnmounted, ref, watch } from "vue"

const isEditing = (element) => element?.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(element?.tagName)

export const useComposer = ({ draft: initial, attachments, send }) => {
  const input = ref(null)
  const draft = ref(initial ?? "")
  const multiline = ref(false)

  // Judged at the single-line layout's padding, whatever the textarea wears now: text that fits only
  // once the controls drop below it would otherwise flip the layout back and forth.
  const wraps = (element) => {
    element.style.padding = getComputedStyle(element).getPropertyValue("--composer-inline-padding")
    const { lineHeight, paddingTop, paddingBottom } = getComputedStyle(element)
    const content = element.scrollHeight - parseFloat(paddingTop) - parseFloat(paddingBottom)
    element.style.padding = ""
    return content > parseFloat(lineHeight) * 1.5
  }

  // A textarea cannot size itself to its content, so measure it after every change.
  const autogrow = () => {
    const element = input.value
    element.style.height = "auto"
    multiline.value = wraps(element)
    const max = parseFloat(getComputedStyle(element).maxHeight)
    element.style.height = `${Math.min(element.scrollHeight, max)}px`
    element.style.overflowY = element.scrollHeight > max ? "auto" : "hidden"
  }

  watch(draft, () => nextTick(autogrow))
  // The layout switch changes the padding, so the height is measured again once it lands.
  watch(multiline, () => nextTick(autogrow))

  let width
  const resize = new ResizeObserver(([entry]) => {
    const nextWidth = entry.borderBoxSize[0].inlineSize
    if (nextWidth === width) return
    width = nextWidth
    autogrow()
  })

  // An image is a message on its own, so text is optional once something is attached.
  const submit = async () => {
    const message = draft.value.trim()
    if (!message && !attachments.sent.value.length) return
    if (!attachments.settled.value) return

    if (await send(message, attachments.sent.value)) {
      draft.value = ""
      attachments.clear()
    }
    input.value.focus()
  }

  const pickExample = ({ currentTarget }) => {
    draft.value = currentTarget.dataset.example
    submit()
  }

  const paste = (event) => {
    const files = Array.from(event.clipboardData?.files ?? [])
    if (files.length) return attachments.add(files)

    nextTick(() => (draft.value = draft.value.replace(/\s+$/, "")))
  }

  const drop = (event) => attachments.add(event.dataTransfer.files)

  const pick = (event) => {
    attachments.add(event.target.files)
    event.target.value = ""
  }

  const typeToFocus = (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey || event.isComposing) return
    if (event.key.length !== 1 || isEditing(document.activeElement)) return

    input.value.focus()
  }

  onMounted(() => {
    autogrow()
    resize.observe(input.value)
    document.addEventListener("keydown", typeToFocus)
  })
  onUnmounted(() => {
    resize.disconnect()
    document.removeEventListener("keydown", typeToFocus)
  })

  return { draft, drop, input, multiline, paste, pick, pickExample, submit }
}
