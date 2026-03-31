import { Controller } from "@hotwired/stimulus"

// Handles: category badges, product image uploads, file uploads, variant section toggling, option types reload
export default class extends Controller {
  static targets = [
    "categoryBadge", "categoryHiddenInputs",
    "mainImageInput", "mainImagePreview", "mainImageHidden",
    "secondaryImageInput", "secondaryImagePreview", "externalHiddenInputs",
    "fileInput", "filePreview", "fileHiddenInputs",
    "toggleVariants", "sectionPrices", "sectionInventory", "sectionDimensions",
    "sectionPrimaryOption", "sectionVariants", "variantWarning",
    "primaryOptionRadios", "addVariantBtn"
  ]

  connect() {
    this.updateVariantSections()
    this.updateTabAccess()
  }

  // ===== TABS =====

  _hasBasicInfo() {
    const nameEl = this.element.querySelector('#product_name')
    const skuEl = this.element.querySelector('#product_sku')
    return nameEl && nameEl.value.trim().length >= 2 && skuEl && skuEl.value.trim().length >= 1
  }

  _hasVariantsEnabled() {
    return this.hasToggleVariantsTarget && this.toggleVariantsTarget.checked
  }

  updateTabAccess() {
    const hasBasic = this._hasBasicInfo()
    const hasVariants = this._hasVariantsEnabled()

    this.element.querySelectorAll('.product-tab').forEach(tab => {
      const tabId = tab.dataset.tab
      if (tabId === 'tab-product') {
        tab.classList.remove('tab-disabled')
        return
      }
      if (tabId === 'tab-variants') {
        const hasExistingVariants = document.querySelectorAll('tr.variant-row-top:not(.variant-destroyed)').length > 0
        const enabled = hasBasic && (hasVariants || hasExistingVariants)
        tab.classList.toggle('tab-disabled', !enabled)
        return
      }
      // Media, Organizare, SEO - need basic info
      tab.classList.toggle('tab-disabled', !hasBasic)
    })
  }

  switchTab(e) {
    const tab = e.currentTarget
    if (tab.classList.contains('tab-disabled')) {
      const hasBasic = this._hasBasicInfo()
      if (!hasBasic) {
        alert('Completeaza mai intai Numele si SKU-ul produsului.')
      } else if (tab.dataset.tab === 'tab-variants' && !this._hasVariantsEnabled()) {
        alert('Bifeaza "Are variante?" in tab-ul Produs.')
      }
      return
    }

    const tabId = tab.dataset.tab

    // Deactivate all tabs and panels
    this.element.querySelectorAll('.product-tab').forEach(t => t.classList.remove('active'))
    this.element.querySelectorAll('.product-tab-panel').forEach(p => p.classList.remove('active'))

    // Activate clicked tab and panel
    tab.classList.add('active')
    const panel = this.element.querySelector('#' + tabId)
    if (panel) panel.classList.add('active')
  }

  // ===== CATEGORIES =====

  toggleCategory(e) {
    const badge = e.currentTarget
    const id = badge.dataset.id
    const wrapper = this.categoryHiddenInputsTarget
    const existing = [...wrapper.querySelectorAll(`input[value="${id}"]`)]

    if (existing.length > 0) {
      existing.forEach(input => input.remove())
      badge.classList.remove("active")
      badge.classList.add("inactive")
    } else {
      this._selectCategory(id, badge, wrapper)

      // Auto-select ancestors
      const ancestorIds = badge.dataset.ancestorIds
      if (ancestorIds) {
        ancestorIds.split(",").filter(Boolean).forEach(ancestorId => {
          const existingAncestor = wrapper.querySelector(`input[value="${ancestorId}"]`)
          if (!existingAncestor) {
            const ancestorBadge = this.element.querySelector(`.category-badge[data-id="${ancestorId}"]`)
            if (ancestorBadge) {
              this._selectCategory(ancestorId, ancestorBadge, wrapper)
            }
          }
        })
      }
    }
  }

  _selectCategory(id, badge, wrapper) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "product[category_ids][]"
    input.value = id
    wrapper.appendChild(input)
    badge.classList.remove("inactive")
    badge.classList.add("active")
  }

  // ===== VARIANT SECTIONS TOGGLE =====

  updateVariantSections() {
    const on = this.hasToggleVariantsTarget && this.toggleVariantsTarget.checked
    const primarySelected = this._hasPrimaryOptionSelected()

    const hasExistingVariants = document.querySelectorAll('tr.variant-row-top:not(.variant-destroyed)').length > 0

    if (this.hasSectionPrimaryOptionTarget) this.sectionPrimaryOptionTarget.style.display = on ? '' : 'none'
    if (this.hasSectionVariantsTarget) this.sectionVariantsTarget.style.display = (on && primarySelected) || hasExistingVariants ? '' : 'none'
    if (this.hasSectionPricesTarget) this.sectionPricesTarget.style.display = on ? 'none' : ''
    if (this.hasSectionInventoryTarget) this.sectionInventoryTarget.style.display = on ? 'none' : ''
    if (this.hasSectionDimensionsTarget) this.sectionDimensionsTarget.style.display = on ? 'none' : ''
    if (this.hasVariantWarningTarget) this.variantWarningTarget.style.display = on ? '' : 'none'

    // Cand bifeaza variante - blocheaza daca are date de produs completate
    if (on) {
      const hasProductData = this._hasProductFieldsFilled()
      if (hasProductData) {
        this.toggleVariantsTarget.checked = false
        this._showToggleWarning('Goleste campurile de pret, stoc si dimensiuni si salveaza produsul, apoi bifeaza "Are variante?".')
        if (this.hasSectionPricesTarget) this.sectionPricesTarget.style.display = ''
        if (this.hasSectionInventoryTarget) this.sectionInventoryTarget.style.display = ''
        if (this.hasSectionDimensionsTarget) this.sectionDimensionsTarget.style.display = ''
        return
      }
      this._hideToggleWarning()
    }

    // Cand debifeaza variante - blocheaza mereu, trebuie sa stearga variantele si sa salveze
    if (!on) {
      const activeVariants = document.querySelectorAll('tr.variant-row-top:not(.variant-destroyed)')
      const destroyedVariants = document.querySelectorAll('tr.variant-row-top.variant-destroyed')

      if (activeVariants.length > 0) {
        // Are variante active - trebuie sterse mai intai
        this.toggleVariantsTarget.checked = true
        this._showToggleWarning('Sterge mai intai toate variantele din tab-ul Variante, apoi salveaza.')
      } else if (destroyedVariants.length > 0) {
        // Variantele sunt marcate pt stergere dar nu sunt salvate
        this.toggleVariantsTarget.checked = true
        this._showToggleWarning('Variantele sunt marcate pentru stergere. Salveaza produsul pentru a confirma stergerea.')
      } else {
        // Nu sunt variante deloc - permite debifarea
        this._hideToggleWarning()
      }

      if (this.toggleVariantsTarget.checked) {
        if (this.hasSectionPricesTarget) this.sectionPricesTarget.style.display = 'none'
        if (this.hasSectionInventoryTarget) this.sectionInventoryTarget.style.display = 'none'
        if (this.hasSectionDimensionsTarget) this.sectionDimensionsTarget.style.display = 'none'
        return
      }
    }

    this.updateTabAccess()
  }

  _hasProductFieldsFilled() {
    const fields = ['product_price', 'product_cost_price', 'product_discount_price',
                    'product_stock', 'product_height', 'product_width', 'product_depth', 'product_weight']
    return fields.some(id => {
      const el = document.getElementById(id)
      return el && el.value && el.value.trim() !== '' && el.value !== '0'
    })
  }

  _clearProductFields() {
    // Goleste campuri text/number
    const fields = ['product_price', 'product_cost_price', 'product_discount_price',
                    'product_vat', 'product_stock', 'product_height', 'product_width',
                    'product_depth', 'product_weight']
    fields.forEach(id => {
      const el = document.getElementById(id)
      if (el) el.value = ''
    })

    // Debifeza checkboxuri
    const checkboxes = ['product_promo_active', 'product_taxable', 'product_coupon_applicable',
                        'product_track_inventory', 'product_sold_individually']
    checkboxes.forEach(id => {
      const el = document.getElementById(id)
      if (el) el.checked = false
    })

    // Reset selecturi la prima optiune
    const selects = ['product_stock_status']
    selects.forEach(id => {
      const el = document.getElementById(id)
      if (el) el.selectedIndex = 0
    })
  }

  _showToggleWarning(message) {
    const toggle = document.getElementById('section-variants-toggle')
    if (!toggle) return
    let warning = toggle.querySelector('.toggle-warning')
    if (!warning) {
      warning = document.createElement('div')
      warning.className = 'toggle-warning'
      warning.style.cssText = 'padding:8px 12px;margin-top:8px;border-radius:4px;font-size:13px;font-weight:500;background:#fff3cd;color:#856404;border:1px solid #ffc107;'
      toggle.querySelector('.section-body').appendChild(warning)
    }
    warning.textContent = message
  }

  _hideToggleWarning() {
    const toggle = document.getElementById('section-variants-toggle')
    if (!toggle) return
    const warning = toggle.querySelector('.toggle-warning')
    if (warning) warning.remove()
  }

  _hasPrimaryOptionSelected() {
    if (!this.hasPrimaryOptionRadiosTarget) return false
    const radios = this.primaryOptionRadiosTarget.querySelectorAll('input[type="radio"]')
    return Array.from(radios).some(r => r.checked)
  }

  // ===== RELOAD OPTION TYPES ON TAB VISIBILITY =====

  reloadOptionTypes() {
    if (document.visibilityState !== 'visible') return
    if (!this.hasToggleVariantsTarget || !this.toggleVariantsTarget.checked) return

    fetch('/admin/option_types.json')
      .then(r => r.json())
      .then(optionTypes => {
        if (!this.hasPrimaryOptionRadiosTarget) return
        const container = this.primaryOptionRadiosTarget
        const currentSelected = container.querySelector('input[type="radio"]:checked')
        const currentSelectedId = currentSelected ? currentSelected.value : null

        container.innerHTML = ''
        optionTypes.forEach(ot => {
          const div = document.createElement('div')
          div.className = 'radio-field'
          const checked = (currentSelectedId && String(ot.id) === String(currentSelectedId)) ? 'checked' : ''
          div.innerHTML = `<input type="radio" name="primary_option_type_id" value="${ot.id}" id="primary_option_type_${ot.id}" ${checked} data-action="change->product-form#updateVariantSections">` +
            `<label for="primary_option_type_${ot.id}">${ot.presentation || ot.name}</label>`
          container.appendChild(div)
        })

        if (this.hasAddVariantBtnTarget) {
          this.addVariantBtnTarget.dataset.optionTypes = JSON.stringify(optionTypes)
        }

        this.updateVariantSections()
      })
      .catch(() => {})
  }

  // ===== PRODUCT IMAGE UPLOADS =====

  async uploadMainImage(e) {
    const file = e.target.files[0]
    if (!file) return
    const parentField = e.target.closest('.form-field')

    this._showUploadStatus(parentField, 'Se incarca imaginea...', false)
    try {
      const cdnUrl = await this._uploadToCdn(file)
      this.mainImageHiddenTarget.value = cdnUrl
      this.mainImagePreviewTarget.innerHTML = ''
      this.mainImagePreviewTarget.appendChild(this._createImageElement(cdnUrl, 'main'))
      this._clearUploadStatus(parentField)
    } catch (err) {
      this._showUploadStatus(parentField, 'Eroare la upload: ' + err.message, true)
    }
  }

  async uploadSecondaryImages(e) {
    const files = e.target.files
    if (!files.length) return
    const parentField = e.target.closest('.form-field')
    let uploaded = 0
    const total = files.length

    this._showUploadStatus(parentField, `Se incarca 0/${total} imagini...`, false)

    for (const file of files) {
      try {
        const cdnUrl = await this._uploadToCdn(file)
        const existingImgs = this.secondaryImagePreviewTarget.querySelectorAll('img')
        const alreadyExists = Array.from(existingImgs).some(img => img.src === cdnUrl)
        if (!alreadyExists) {
          const hidden = document.createElement('input')
          hidden.type = 'hidden'
          hidden.name = 'product[external_image_urls][]'
          hidden.value = cdnUrl
          this.externalHiddenInputsTarget.appendChild(hidden)
          this.secondaryImagePreviewTarget.appendChild(this._createImageElement(cdnUrl, 'secondary', uploaded))
        }
      } catch (err) {}
      uploaded++
      this._showUploadStatus(parentField, `Se incarca ${uploaded}/${total} imagini...`, false)
    }

    this._clearUploadStatus(parentField)
    e.target.value = ''
  }

  removeImage(e) {
    const target = e.target.dataset.target || e.currentTarget.dataset.target
    if (target === 'main') {
      this.mainImageHiddenTarget.value = ''
      this.mainImagePreviewTarget.innerHTML = ''
    }
    if (target === 'secondary') {
      const container = e.target.closest('.bunny-preview')
      const img = container.querySelector('img')
      const url = img.src
      const hiddenInputs = this.externalHiddenInputsTarget.querySelectorAll('input')
      hiddenInputs.forEach(input => { if (input.value === url) input.remove() })
      container.remove()
    }
  }

  // ===== FILE UPLOADS =====

  async uploadFiles(e) {
    const files = e.target.files
    if (!files.length) return

    for (const file of files) {
      try {
        const cdnUrl = await this._uploadToCdn(file)
        const exists = [...this.fileHiddenInputsTarget.querySelectorAll('input')].some(i => i.value === cdnUrl)
        if (exists) continue

        const hidden = document.createElement('input')
        hidden.type = 'hidden'
        hidden.name = 'product[external_file_urls][]'
        hidden.value = cdnUrl
        this.fileHiddenInputsTarget.appendChild(hidden)

        const wrapper = document.createElement('div')
        wrapper.className = 'file-preview-item'
        const link = document.createElement('a')
        link.href = cdnUrl
        link.target = '_blank'
        link.rel = 'noopener'
        link.textContent = file.name
        const removeBtn = document.createElement('button')
        removeBtn.className = 'remove-btn'
        removeBtn.textContent = '\u00d7'
        removeBtn.type = 'button'
        removeBtn.dataset.url = cdnUrl
        removeBtn.dataset.action = 'click->product-form#removeFile'
        wrapper.appendChild(link)
        wrapper.appendChild(removeBtn)
        this.filePreviewTarget.appendChild(wrapper)
      } catch (err) {}
    }
    e.target.value = ''
  }

  removeFile(e) {
    const url = e.target.dataset.url || e.currentTarget.dataset.url
    this.fileHiddenInputsTarget.querySelectorAll('input').forEach(input => {
      if (input.value === url) input.remove()
    })
    const card = e.target.closest('.file-preview-item')
    if (card) card.remove()
  }

  // ===== PRIVATE HELPERS =====

  async _uploadToCdn(file) {
    const uniqueName = Date.now() + '_' + encodeURIComponent(file.name)
    const res = await fetch('/uploads/presign?filename=' + uniqueName)
    const { upload_url, headers } = await res.json()

    const upload = await fetch(upload_url, {
      method: 'PUT',
      headers: { 'Content-Type': headers['Content-Type'], 'AccessKey': headers['AccessKey'] },
      body: file
    })

    if (!upload.ok) throw new Error('Upload failed')
    const path = new URL(upload_url).pathname.split('/').slice(2).join('/')
    return 'https://ayus-cdn.b-cdn.net/' + path
  }

  _createImageElement(url, type, index = null) {
    const div = document.createElement('div')
    div.className = 'image-preview-item bunny-preview'
    div.dataset.type = type
    if (index !== null) div.dataset.index = index

    const img = document.createElement('img')
    img.src = url
    img.style[type === 'main' ? 'maxHeight' : 'width'] = type === 'main' ? '120px' : '100px'

    const btn = document.createElement('button')
    btn.className = 'remove-btn'
    btn.textContent = '\u00d7'
    btn.type = 'button'
    btn.dataset.target = type
    btn.dataset.action = 'click->product-form#removeImage'

    div.appendChild(img)
    div.appendChild(btn)
    return div
  }

  _showUploadStatus(container, message, isError) {
    let status = container.querySelector('.upload-status')
    if (!status) {
      status = document.createElement('div')
      status.className = 'upload-status'
      status.style.cssText = 'padding:6px 12px;margin-top:6px;border-radius:4px;font-size:13px;font-weight:500;'
      container.appendChild(status)
    }
    status.textContent = message
    status.style.background = isError ? '#f8d7da' : '#d1ecf1'
    status.style.color = isError ? '#721c24' : '#0c5460'
  }

  _clearUploadStatus(container) {
    const status = container.querySelector('.upload-status')
    if (status) status.remove()
  }
}
