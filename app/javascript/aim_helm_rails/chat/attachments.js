import { computed, markRaw, reactive } from "vue"
import { csrfToken } from "aim_helm_rails/chat/transport"

const ACCEPTED = /^(image\/|application\/pdf$|application\/vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet$)/

// Each file uploads the moment it arrives, so a send carries gids rather than bytes.
export const useAttachments = (path) => {
  const items = reactive([])

  const add = (files) => {
    Array.from(files)
      .filter((file) => ACCEPTED.test(file.type))
      .forEach((file) => {
        const item = reactive({
          error: null,
          file: markRaw(file),
          gid: null,
          id: crypto.randomUUID(),
          name: file.name,
          previewUrl: null,
          status: "uploading",
          thumbnailUrl: file.type.startsWith("image/") ? URL.createObjectURL(file) : null,
        })
        items.push(item)
        upload(item)
      })
  }

  const upload = async (item) => {
    const body = new FormData()
    body.append("files[]", item.file, item.name)

    try {
      const response = await fetch(path, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken() },
        body,
      })
      const payload = await response.json()

      if (!response.ok) return Object.assign(item, { error: payload.error, status: "failed" })

      // The stored thumbnail replaces the local preview, so a sent message keeps showing the file.
      const { gid, thumbnail_url: thumbnailUrl, url: previewUrl } = payload.attachments[0]
      if (item.thumbnailUrl) URL.revokeObjectURL(item.thumbnailUrl)
      Object.assign(item, { gid, previewUrl, status: "uploaded", thumbnailUrl })
    } catch {
      Object.assign(item, { error: "Upload failed — check your connection.", status: "failed" })
    }
  }

  const retry = (item) => {
    Object.assign(item, { error: null, status: "uploading" })
    upload(item)
  }

  const discard = (item) => {
    if (item.status !== "uploaded" && item.thumbnailUrl) URL.revokeObjectURL(item.thumbnailUrl)
    items.splice(items.indexOf(item), 1)
  }

  const clear = () => {
    items.slice().forEach(discard)
  }

  return {
    add,
    attachments: items,
    clear,
    discard,
    sent: computed(() =>
      items
        .filter((item) => item.gid)
        .map(({ gid, name, previewUrl, thumbnailUrl }) => ({
          gid,
          name,
          thumbnail_url: thumbnailUrl,
          url: previewUrl,
        })),
    ),
    retry,
    settled: computed(() => items.every((item) => item.status === "uploaded")),
  }
}
