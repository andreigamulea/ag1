import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    endpoint: String,
    filterId: String
  }

  static targets = ["input", "dropdown"]

  connect() {
    this.validSuggestions = []

    if (!this.inputTarget || !this.dropdownTarget) return

    this.inputTarget.dataset.selected = "false"

    this.inputTarget.addEventListener("input", () => this.onInput())
    this.inputTarget.addEventListener("blur", () => this.onBlur())
    document.addEventListener("click", (e) => this.onClickOutside(e))
  }

  onInput() {
    const query = this.inputTarget.value.trim()
    this.inputTarget.dataset.selected = "false"

    const isRomania = this.getTaraValue().toLowerCase() === "romania"
    if ((this.inputTarget.id.includes("judet") || this.inputTarget.id.includes("localitate")) && !isRomania) {
      this.dropdownTarget.innerHTML = ''
      this.dropdownTarget.style.display = 'none'
      return
    }

    if (query.length > 1) {
      let url = `${this.endpointValue}?q=${encodeURIComponent(query)}`
      if (this.hasFilterIdValue) {
        const filterInput = document.getElementById(this.filterIdValue)
        const filterValue = filterInput?.value?.trim()
        if (filterValue) url += `&filter=${encodeURIComponent(filterValue)}`
      }

      fetch(url)
        .then(res => res.json())
        .then(data => {
          this.validSuggestions = data
          this.dropdownTarget.innerHTML = ''
          if (data.length > 0) {
            this.dropdownTarget.style.display = 'block'
            data.forEach(item => {
              const option = document.createElement('a')
              option.classList.add('dropdown-item')
              option.href = '#'
              option.textContent = item
              option.addEventListener("click", e => {
                e.preventDefault()
                this.inputTarget.value = item
                this.inputTarget.dataset.selected = "true"
                this.dropdownTarget.style.display = 'none'
              })
              this.dropdownTarget.appendChild(option)
            })
          } else {
            this.dropdownTarget.style.display = 'none'
          }
        })
    } else {
      this.validSuggestions = []
      this.dropdownTarget.style.display = 'none'
    }
  }

  onBlur() {
    setTimeout(() => {
      const selected = this.inputTarget.dataset.selected === "true"
      const isRomania = this.getTaraValue().toLowerCase() === "romania"
      const id = this.inputTarget.id

      if (!selected) {
        if (
          id.includes("tara") ||
          (id.includes("judet") && isRomania) ||
          (id.includes("localitate") && isRomania)
        ) {
          this.inputTarget.value = ''
          if (id.includes("localitate")) {
            const prefix = id.includes("shipping") ? "shipping_" : ""
            const judetInput = document.getElementById(`${prefix}judet_input`)
            if (judetInput) judetInput.value = ''
          }
        }
      }

      this.inputTarget.dataset.selected = "false"
    }, 200)
  }

  onClickOutside(event) {
    if (!this.dropdownTarget.contains(event.target) && event.target !== this.inputTarget) {
      this.dropdownTarget.style.display = 'none'
    }
  }

  getTaraValue() {
    const id = this.inputTarget.id
    if (id.includes("shipping")) {
      return document.getElementById("shipping_tara_input")?.value || ""
    } else {
      return document.getElementById("tara_input")?.value || ""
    }
  }
}
