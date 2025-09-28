import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "fields"]

  connect() {
    console.log("ToggleShipping controller CONECTAT! Checkbox găsit?", !!this.checkboxTarget, "Fields găsit?", !!this.fieldsTarget);  // Log să vezi dacă rulează

    this.toggle();
  }

  toggle() {
    console.log("Toggle apelat! Checked?", this.checkboxTarget.checked);  // Log starea

    if (this.checkboxTarget.checked) {
      this.fieldsTarget.style.display = "block"
    } else {
      this.fieldsTarget.style.display = "none"
    }
  }
}