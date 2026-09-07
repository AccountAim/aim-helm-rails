import { Controller } from "@hotwired/stimulus"

// Loads the chat island and nothing else: Vue arrives on demand, so only a chat page pays for it,
// and the island lives and dies with this controller — which is what keeps Turbo's cached page from
// mounting it twice.
export default class extends Controller {
  static targets = ["events", "island"]
  static values = {
    autosubmit: Boolean,
    context: Boolean,
    draft: String,
    helmsman: String,
    helmsmen: Array,
    history: Array,
    pane: Object,
    path: String,
    sessionId: String,
    uploadPath: String,
  }

  connect() {
    this.chat = import("aim_helm_rails/chat/app").then(({ mountChat }) =>
      mountChat({
        autosubmit: this.autosubmitValue,
        context: this.contextValue,
        pane: this.paneValue,
        draft: this.draftValue,
        events: this.eventsTarget,
        helmsman: this.helmsmanValue,
        helmsmen: this.helmsmenValue,
        path: this.pathValue,
        root: this.islandTarget,
        runs: this.historyValue,
        sessionId: this.sessionIdValue,
        uploadPath: this.uploadPathValue,
      }),
    )
  }

  disconnect() {
    this.chat.then((chat) => chat.unmount())
  }
}
