import { onMounted, onUnmounted } from "vue"

export const csrfToken = () => document.querySelector("meta[name=csrf-token]")?.content

// Every post goes to the chat's messages path; the first one creates the chat, and its response
// names it. A chat opened on something posts nothing at first, so the agent can start on it.
export const useChatTransport = ({ store, session, events, helmsman, context, path, pin, receive }) => {
  const onEvent = ({ detail }) => receive(detail)

  onMounted(() => {
    events.addEventListener("agent:event", onEvent)
    if (!session.value && context) send("")
  })
  onUnmounted(() => events.removeEventListener("agent:event", onEvent))

  const post = (message, attachments) => {
    const body = new URLSearchParams({ "message[content]": message, "message[helmsman]": helmsman.value.name })
    attachments.forEach(({ gid }) => body.append("message[attachments][]", gid))

    return fetch(path, {
      method: "POST",
      headers: { "X-CSRF-Token": csrfToken(), "Content-Type": "application/x-www-form-urlencoded" },
      body,
    })
  }

  const adopt = (headers) => {
    session.value = headers.get("X-Agent-Session-Id")
    events.dispatchEvent(
      new CustomEvent("agent:chat-created", { bubbles: true, detail: { path: headers.get("X-Agent-Session-Path") } }),
    )
    // Opened on something, the chat comes back with its first pin.
    const pane = JSON.parse(headers.get("X-Agent-Context-Pane"))
    if (pane.src) pin(pane)
  }

  const send = async (message, attachments = []) => {
    const sending = Boolean(message || attachments.length)
    if (sending) store.addPending(message, attachments)

    const { ok, headers } = await post(message, attachments)
    if (!ok) {
      store.removePending()
      return false
    }

    if (!session.value) adopt(headers)
    if (sending) store.bindPending(headers.get("X-Agent-Run-Id"))
    return true
  }

  return { send }
}
