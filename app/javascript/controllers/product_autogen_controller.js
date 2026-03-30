import { Controller } from "@hotwired/stimulus"

// Handles: auto-generation of slug/SKU from product name, variant SKU auto-generation, uniqueness checks
export default class extends Controller {
  static targets = ["name", "slug", "sku", "slugStatus", "skuStatus", "slugAutoBtn", "skuAutoBtn"]
  static values = { productId: String }

  connect() {
    this.isNewProduct = !this.slugTarget.value.trim()
    this.slugManuallyEdited = false
    this.skuManuallyEdited = false
    this.slugCheckTimer = null
    this.skuCheckTimer = null
    this.variantSkuManualEdits = {}
    this.variantSkuCheckTimers = {}
  }

  // ===== PARAMETERIZE HELPER =====

  _parameterize(str) {
    return str.toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '')
  }

  // ===== AUTO-GENERATE FROM NAME =====

  nameChanged() {
    const val = this.nameTarget.value.trim()
    if (!val) return

    if (this.isNewProduct && !this.slugManuallyEdited) {
      this.slugTarget.value = this._parameterize(val)
      clearTimeout(this.slugCheckTimer)
      this.slugCheckTimer = setTimeout(() => this._checkSlugUniqueness(), 600)
    }

    if (this.isNewProduct && !this.skuManuallyEdited) {
      this.skuTarget.value = this._parameterize(val).toUpperCase()
      clearTimeout(this.skuCheckTimer)
      this.skuCheckTimer = setTimeout(() => this._checkSkuUniqueness(), 600)
    }

    this._regenerateAllVariantSkus()
  }

  // ===== SLUG MANUAL EDIT =====

  slugChanged() {
    this.slugManuallyEdited = true
    if (this.hasSlugAutoBtnTarget) this.slugAutoBtnTarget.style.display = 'inline-block'
    clearTimeout(this.slugCheckTimer)
    this.slugCheckTimer = setTimeout(() => this._checkSlugUniqueness(), 600)
  }

  slugBlur() {
    if (this.slugTarget.value.trim()) this._checkSlugUniqueness()
  }

  resetSlug() {
    this.slugManuallyEdited = false
    if (this.hasSlugAutoBtnTarget) this.slugAutoBtnTarget.style.display = 'none'
    const val = this.nameTarget.value.trim()
    if (val) {
      this.slugTarget.value = this._parameterize(val)
      this._checkSlugUniqueness()
    }
  }

  // ===== SKU MANUAL EDIT =====

  skuChanged() {
    this.skuManuallyEdited = true
    if (this.hasSkuAutoBtnTarget) this.skuAutoBtnTarget.style.display = 'inline-block'
    clearTimeout(this.skuCheckTimer)
    this.skuCheckTimer = setTimeout(() => this._checkSkuUniqueness(), 600)
    this._regenerateAllVariantSkus()
  }

  skuBlur() {
    if (this.skuTarget.value.trim()) this._checkSkuUniqueness()
  }

  resetSku() {
    this.skuManuallyEdited = false
    if (this.hasSkuAutoBtnTarget) this.skuAutoBtnTarget.style.display = 'none'
    const val = this.nameTarget.value.trim()
    if (val) {
      this.skuTarget.value = this._parameterize(val).toUpperCase()
      this._checkSkuUniqueness()
    }
  }

  // ===== VARIANT SKU AUTO-GENERATION =====

  variantOptionChanged(e) {
    const topRow = e.target.closest('tr.variant-row-top')
    if (topRow) this._autoGenerateVariantSku(topRow)
  }

  variantSkuChanged(e) {
    this.variantSkuManualEdits[e.target.name] = true
    const btn = e.target.closest('td').querySelector('.variant-sku-auto-btn')
    if (btn) btn.style.display = 'inline-block'
    clearTimeout(this.variantSkuCheckTimers[e.target.name])
    this.variantSkuCheckTimers[e.target.name] = setTimeout(() => this._checkVariantSkuUniqueness(e.target), 600)
  }

  variantSkuBlur(e) {
    if (e.target.value.trim()) this._checkVariantSkuUniqueness(e.target)
  }

  resetVariantSku(e) {
    const topRow = e.target.closest('tr.variant-row-top')
    if (!topRow) return
    const skuInput = topRow.querySelector('input.variant-sku')
    if (skuInput) {
      delete this.variantSkuManualEdits[skuInput.name]
      e.target.style.display = 'none'
      const statusEl = topRow.querySelector('.variant-sku-status')
      if (statusEl) statusEl.style.display = 'none'
      this._autoGenerateVariantSku(topRow)
    }
  }

  // ===== PRIVATE: UNIQUENESS CHECKS =====

  _checkSlugUniqueness() {
    const slug = this.slugTarget.value.trim()
    const statusEl = this.slugStatusTarget
    if (!slug) { statusEl.style.display = 'none'; return }

    let url = '/products/check_slug?slug=' + encodeURIComponent(slug)
    if (this.productIdValue) url += '&product_id=' + this.productIdValue

    fetch(url)
      .then(r => r.json())
      .then(data => {
        statusEl.style.display = 'block'
        if (data.available) {
          statusEl.style.color = '#28a745'
          statusEl.textContent = '\u2713 URL disponibil'
        } else {
          this.slugTarget.value = data.slug
          statusEl.style.color = '#dc8a00'
          statusEl.textContent = '\u26A0 URL ocupat, sugerat: ' + data.slug
        }
      })
      .catch(() => { statusEl.style.display = 'none' })
  }

  _checkSkuUniqueness() {
    const sku = this.skuTarget.value.trim()
    const statusEl = this.skuStatusTarget
    if (!sku) { statusEl.style.display = 'none'; return }

    let url = '/products/check_sku?sku=' + encodeURIComponent(sku)
    if (this.productIdValue) url += '&product_id=' + this.productIdValue

    fetch(url)
      .then(r => r.json())
      .then(data => {
        statusEl.style.display = 'block'
        if (data.available) {
          statusEl.style.color = '#28a745'
          statusEl.textContent = '\u2713 SKU disponibil'
        } else {
          this.skuTarget.value = data.sku
          statusEl.style.color = '#dc8a00'
          statusEl.textContent = '\u26A0 SKU ocupat, sugerat: ' + data.sku
        }
      })
      .catch(() => { statusEl.style.display = 'none' })
  }

  _autoGenerateVariantSku(topRow) {
    const skuInput = topRow.querySelector('input[name*="[sku]"]')
    if (!skuInput) return
    if (this.variantSkuManualEdits[skuInput.name]) return

    const productName = this.nameTarget.value.trim()
    const baseSku = productName ? this._parameterize(productName).toUpperCase() : (this.skuTarget.value.trim() || 'VAR')
    const selects = topRow.querySelectorAll('select[name*="option_value_ids"]')
    const parts = [baseSku]

    selects.forEach(sel => {
      const text = sel.options[sel.selectedIndex] ? sel.options[sel.selectedIndex].text.trim() : ''
      if (text && text !== '-- alege --') {
        const abbr = this._parameterize(text).substring(0, 3).toUpperCase()
        if (abbr) parts.push(abbr)
      }
    })

    if (parts.length === 1) {
      const allTopRows = document.querySelectorAll('tr.variant-row-top:not(.variant-destroyed)')
      const idx = Array.from(allTopRows).indexOf(topRow) + 1
      parts.push('V' + idx)
    }

    skuInput.value = parts.join('-')
    this._checkVariantSkuUniqueness(skuInput)
  }

  _regenerateAllVariantSkus() {
    document.querySelectorAll('tr.variant-row-top:not(.variant-destroyed)').forEach(topRow => {
      this._autoGenerateVariantSku(topRow)
    })
  }

  _checkVariantSkuUniqueness(input) {
    const sku = input.value.trim()
    const statusEl = input.closest('td').querySelector('.variant-sku-status')
    if (!sku || !statusEl) { if (statusEl) statusEl.style.display = 'none'; return }

    // Local duplicate check
    const allSkuInputs = document.querySelectorAll('input.variant-sku')
    let localDuplicate = false
    allSkuInputs.forEach(other => {
      if (other !== input && other.value.trim().toUpperCase() === sku.toUpperCase()) {
        const otherRow = other.closest('tr')
        if (otherRow && !otherRow.classList.contains('variant-destroyed')) localDuplicate = true
      }
    })

    if (localDuplicate) {
      const baseSku = sku.replace(/-\d+$/, '')
      let counter = 2, candidate
      while (true) {
        candidate = baseSku + '-' + counter
        let taken = false
        allSkuInputs.forEach(other => {
          if (other !== input && other.value.trim().toUpperCase() === candidate.toUpperCase()) {
            const otherRow = other.closest('tr')
            if (otherRow && !otherRow.classList.contains('variant-destroyed')) taken = true
          }
        })
        if (!taken) break
        counter++
      }
      input.value = candidate
      statusEl.style.display = 'block'
      statusEl.style.color = '#dc8a00'
      statusEl.textContent = '\u26A0 SKU duplicat, sugerat: ' + candidate
      this._checkVariantSkuUniqueness(input)
      return
    }

    // DB check
    const variantId = input.dataset.variantId || ''
    const formEl = document.querySelector('form[action*="products"]')
    let pId = ''
    if (formEl) {
      const match = formEl.action.match(/products\/(\d+)/)
      if (match) pId = match[1]
    }

    let url = '/products/check_variant_sku?sku=' + encodeURIComponent(sku)
    if (variantId) url += '&variant_id=' + variantId
    if (pId) url += '&product_id=' + pId

    fetch(url)
      .then(r => r.json())
      .then(data => {
        statusEl.style.display = 'block'
        if (data.available) {
          statusEl.style.color = '#28a745'
          statusEl.textContent = '\u2713 SKU disponibil'
        } else {
          input.value = data.sku
          statusEl.style.color = '#dc8a00'
          statusEl.textContent = '\u26A0 SKU ocupat, sugerat: ' + data.sku
        }
      })
      .catch(() => { statusEl.style.display = 'none' })
  }
}
