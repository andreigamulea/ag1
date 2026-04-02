import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "buttonContainer", "spinner"]
  static values = { url: String, hasNext: Boolean }

  load() {
    if (!this.hasNextValue) return

    this.buttonTarget.style.display = "none"
    this.spinnerTarget.style.display = "inline-block"

    fetch(this.urlValue, {
      headers: {
        "X-Load-More": "true",
        "Accept": "text/html"
      }
    })
      .then(response => response.text())
      .then(html => {
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, "text/html")
        const cards = doc.querySelectorAll(".product-card")
        const grid = document.getElementById("products-grid")

        cards.forEach(card => grid.appendChild(card))

        // Check for next page metadata
        const meta = doc.querySelector("[data-next-page-url]")
        if (meta && meta.dataset.hasNext === "true") {
          this.urlValue = meta.dataset.nextPageUrl
          this.hasNextValue = true
          this.buttonTarget.style.display = "inline-block"
        } else {
          this.hasNextValue = false
          this.buttonContainerTarget.style.display = "none"
        }

        this.spinnerTarget.style.display = "none"
      })
      .catch(() => {
        this.buttonTarget.style.display = "inline-block"
        this.spinnerTarget.style.display = "none"
      })
  }
}
