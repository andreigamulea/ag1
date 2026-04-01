import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "fields"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (this.checkboxTarget.checked) {
      this.fieldsTarget.style.display = "block"
    } else {
      this.fieldsTarget.style.display = "none"
    }
  }
}
