import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form"]

  toggle(event) {
    const card = event.currentTarget.dataset.card
    const display = this.displayTargets.find(el => el.dataset.card === card)
    const form = this.formTargets.find(el => el.dataset.card === card)

    if (!display || !form) return

    if (form.style.display === "none") {
      display.style.display = "none"
      form.style.display = "block"
      const firstInput = form.querySelector("input:not([type=hidden])")
      if (firstInput) firstInput.focus()
    } else {
      form.style.display = "none"
      display.style.display = "flex"
    }
  }
}
