import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    type: String,
    payload: String,
    runId: String,
    sessionId: String,
    turnId: String,
  }

  connect() {
    this.dispatch("event", {
      prefix: "agent",
      detail: {
        name: this.typeValue,
        runId: this.runIdValue,
        sessionId: this.sessionIdValue,
        turnId: this.turnIdValue,
        payload: JSON.parse(this.payloadValue),
      },
    })

    this.element.remove()
  }
}
