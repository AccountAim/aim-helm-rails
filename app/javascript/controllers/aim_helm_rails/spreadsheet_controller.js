import { Controller } from "@hotwired/stimulus"

const ROWS = 500
const TAB = "rounded px-3 py-1"
const ACTIVE_TAB = "bg-primary text-primary-foreground"
const INACTIVE_TAB = "bg-muted"

// Draws one sheet of a workbook as a table; page count, loading, and error ride on the element
// as data attributes for the preview camera.
export default class extends Controller {
  static targets = ["tabs", "sheet"]
  static values = { url: String, index: Number }

  async connect() {
    try {
      const { read, utils } = await import("xlsx")
      this.utils = utils
      this.workbook = read(await (await fetch(this.urlValue)).arrayBuffer())
      this.element.dataset.pageCount = this.workbook.SheetNames.length
      this.tabsTarget.replaceChildren(...this.workbook.SheetNames.map((name, index) => this.tab(name, index)))
      this.draw()
    } catch (error) {
      this.element.dataset.error = error.message
    } finally {
      delete this.element.dataset.loading
    }
  }

  select(event) {
    this.indexValue = Number(event.currentTarget.dataset.index)
  }

  indexValueChanged() {
    if (this.workbook) this.draw()
  }

  draw() {
    const names = this.workbook.SheetNames
    if (this.indexValue >= names.length) {
      throw new Error(`Page index ${this.indexValue} is outside the available range (0-${names.length - 1})`)
    }

    const rows = this.utils.sheet_to_json(this.workbook.Sheets[names[this.indexValue]], {
      header: 1,
      raw: false,
      defval: "",
    })
    this.sheetTarget.replaceChildren(this.table(rows.slice(0, ROWS)), ...this.footer(rows.length))
    this.tabsTarget.querySelectorAll("button").forEach((tab, index) => {
      const active = index === this.indexValue
      tab.setAttribute("aria-selected", active)
      tab.className = `${TAB} ${active ? ACTIVE_TAB : INACTIVE_TAB}`
    })
  }

  tab(name, index) {
    const button = document.createElement("button")
    button.type = "button"
    button.role = "tab"
    button.dataset.index = index
    button.dataset.action = "aim-helm-rails--spreadsheet#select"
    button.textContent = name
    return button
  }

  table(rows) {
    const table = document.createElement("table")
    table.className = "border-collapse font-mono text-sm"
    rows.forEach((values) => {
      const row = table.insertRow()
      values.forEach((value) => {
        const cell = row.insertCell()
        cell.className = "min-w-32 whitespace-nowrap border px-2 py-1"
        cell.textContent = value
      })
    })
    return table
  }

  footer(total) {
    if (total <= ROWS) return []

    const note = document.createElement("p")
    note.className = "p-2 text-xs text-muted-foreground"
    note.textContent = `Showing the first ${ROWS} of ${total} rows.`
    return [note]
  }
}
