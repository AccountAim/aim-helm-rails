import { Controller } from "@hotwired/stimulus"

const OUTPUT_SCALE = 2

// Draws one page of a PDF; page count, loading, and error ride on the element as data attributes
// for the preview camera.
export default class extends Controller {
  static targets = ["canvas", "navigation", "previous", "next", "status"]
  static values = { url: String, index: Number }

  async connect() {
    try {
      const { getDocument, GlobalWorkerOptions } = await import("pdfjs-dist")
      GlobalWorkerOptions.workerSrc = new URL("pdf.worker.mjs", import.meta.resolve("pdfjs-dist")).href
      this.pdf = await getDocument({ url: this.urlValue }).promise
      this.element.dataset.pageCount = this.pdf.numPages
      this.navigationTarget.hidden = this.pdf.numPages === 1
      await this.draw()
    } catch (error) {
      this.element.dataset.error = error.message
    } finally {
      delete this.element.dataset.loading
    }
  }

  previous() {
    this.indexValue -= 1
  }

  next() {
    this.indexValue += 1
  }

  indexValueChanged() {
    if (this.pdf) this.draw()
  }

  async draw() {
    if (this.indexValue >= this.pdf.numPages) {
      throw new Error(`Page index ${this.indexValue} is outside the available range (0-${this.pdf.numPages - 1})`)
    }

    this.previousTarget.disabled = this.nextTarget.disabled = true
    const page = await this.pdf.getPage(this.indexValue + 1)
    const viewport = page.getViewport({ scale: 1 })
    const canvas = this.canvasTarget
    canvas.width = Math.floor(viewport.width * OUTPUT_SCALE)
    canvas.height = Math.floor(viewport.height * OUTPUT_SCALE)
    canvas.style.width = `${viewport.width}px`

    await page.render({
      canvasContext: canvas.getContext("2d"),
      intent: "print",
      transform: [OUTPUT_SCALE, 0, 0, OUTPUT_SCALE, 0, 0],
      viewport,
    }).promise

    this.statusTarget.textContent = `Page ${this.indexValue + 1} of ${this.pdf.numPages}`
    this.previousTarget.disabled = this.indexValue === 0
    this.nextTarget.disabled = this.indexValue + 1 >= this.pdf.numPages
  }
}
