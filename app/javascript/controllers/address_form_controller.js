import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "taraInput", "taraDropdown",
    "judetInput", "judetDropdown",
    "localitateInput", "localitateDropdown"
  ]

  connect() {
    this.setupAutocomplete(this.taraInputTarget, this.taraDropdownTarget, "/autocomplete_tara")
    this.setupAutocomplete(this.judetInputTarget, this.judetDropdownTarget, "/autocomplete_judet")
    this.setupAutocomplete(this.localitateInputTarget, this.localitateDropdownTarget, "/autocomplete_localitate", this.judetInputTarget)
    this.initializeFields()
  }

  initializeFields() {
    const tara = this.taraInputTarget.value.trim().toLowerCase()

    if (!this.taraInputTarget.value || this.taraInputTarget.value === "") {
      this.taraInputTarget.value = "Romania"
    }

    if (tara === "romania" || tara === "românia") {
      this.judetInputTarget.disabled = false
      this.judetInputTarget.placeholder = "Tasteaza max 2 litere si selecteaza..."
      this.localitateInputTarget.placeholder = "Tasteaza max 2 litere si selecteaza..."
    } else if (tara) {
      this.judetInputTarget.disabled = false
      this.localitateInputTarget.disabled = false
      this.judetInputTarget.placeholder = "Introduceti judetul/regiunea..."
      this.localitateInputTarget.placeholder = "Introduceti localitatea..."
    }

    if (this.judetInputTarget.value.trim() !== "") {
      this.judetInputTarget.disabled = false
    }
    if (this.localitateInputTarget.value.trim() !== "") {
      this.localitateInputTarget.disabled = false
    }
  }

  setupAutocomplete(input, dropdown, endpoint, filterInput = null) {
    let debounceTimer

    input.addEventListener("input", () => {
      clearTimeout(debounceTimer)
      const query = input.value.trim()

      const isRomania = this.isRomania()

      if ((input === this.judetInputTarget || input === this.localitateInputTarget) && !isRomania) {
        dropdown.innerHTML = ""
        dropdown.style.display = "none"
        return
      }

      if (query.length > 1) {
        debounceTimer = setTimeout(() => {
          let url = `${endpoint}?q=${encodeURIComponent(query)}`
          if (filterInput) {
            const filterValue = filterInput.value.trim()
            if (filterValue) url += `&filter=${encodeURIComponent(filterValue)}`
          }

          fetch(url)
            .then(res => res.json())
            .then(data => {
              dropdown.innerHTML = ""
              if (data.length > 0) {
                dropdown.style.display = "block"
                data.forEach(item => {
                  const option = document.createElement("a")
                  option.classList.add("dropdown-item")
                  option.href = "#"
                  option.textContent = item
                  option.addEventListener("click", (e) => {
                    e.preventDefault()
                    input.value = item
                    dropdown.style.display = "none"
                    this.onSelect(input)
                  })
                  dropdown.appendChild(option)
                })
              } else {
                dropdown.style.display = "none"
              }
            })
            .catch(() => { dropdown.style.display = "none" })
        }, 200)
      } else {
        dropdown.style.display = "none"
      }
    })

    input.addEventListener("blur", () => {
      setTimeout(() => { dropdown.style.display = "none" }, 200)
    })

    document.addEventListener("click", (e) => {
      if (!dropdown.contains(e.target) && e.target !== input) {
        dropdown.style.display = "none"
      }
    })
  }

  onSelect(input) {
    if (input === this.taraInputTarget) {
      this.enableNextFields()
    } else if (input === this.judetInputTarget) {
      this.localitateInputTarget.disabled = false
      this.localitateInputTarget.value = ""
      this.localitateInputTarget.focus()
    }
  }

  enableNextFields() {
    const tara = this.taraInputTarget.value.trim().toLowerCase()

    if (tara === "romania" || tara === "românia") {
      this.judetInputTarget.disabled = false
      this.judetInputTarget.readOnly = false
      this.judetInputTarget.value = ""
      this.localitateInputTarget.disabled = true
      this.localitateInputTarget.value = ""
      this.judetInputTarget.placeholder = "Tasteaza max 2 litere si selecteaza..."
      this.localitateInputTarget.placeholder = "Tasteaza max 2 litere si selecteaza..."
      this.judetInputTarget.focus()
    } else {
      this.judetInputTarget.disabled = false
      this.judetInputTarget.readOnly = false
      this.judetInputTarget.value = ""
      this.localitateInputTarget.disabled = false
      this.localitateInputTarget.readOnly = false
      this.localitateInputTarget.value = ""
      this.judetInputTarget.placeholder = "Introduceti judetul/regiunea..."
      this.localitateInputTarget.placeholder = "Introduceti localitatea..."
      this.judetInputTarget.focus()
    }
  }

  isRomania() {
    const tara = this.taraInputTarget.value.trim().toLowerCase()
    return tara === "romania" || tara === "românia"
  }
}
