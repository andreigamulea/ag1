import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  minus(e) {
    e.preventDefault()
    const cartKey = e.currentTarget.dataset.cartKey
    const input = this.element.querySelector(`input[data-cart-key="${cartKey}"]`)
    if (input) {
      const val = parseInt(input.value) || 1
      if (val > 1) input.value = val - 1
    }
  }

  plus(e) {
    e.preventDefault()
    const cartKey = e.currentTarget.dataset.cartKey
    const input = this.element.querySelector(`input[data-cart-key="${cartKey}"]`)
    if (input) {
      input.value = (parseInt(input.value) || 1) + 1
    }
  }

  submitForm(e) {
    e.preventDefault()
    const form = e.currentTarget
    const formData = new FormData(form)
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content
    fetch(form.action, {
      method: 'POST',
      headers: { 'X-CSRF-Token': csrfToken, 'Accept': 'application/json' },
      body: formData,
      credentials: 'same-origin'
    }).then(response => {
      if (response.ok) window.location.reload()
      else alert('Eroare la actualizare.')
    })
  }

  remove(e) {
    e.preventDefault()
    const cartKey = e.currentTarget.dataset.cartKey
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content
    fetch('/cart/remove', {
      method: 'POST',
      headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ cart_key: cartKey }),
      credentials: 'same-origin'
    }).then(response => {
      if (response.ok) window.location.reload()
      else alert('Eroare la stergere.')
    })
  }
}
