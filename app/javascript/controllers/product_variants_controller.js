import { Controller } from "@hotwired/stimulus"

// Handles: add/remove/duplicate variants, variant image upload/remove
export default class extends Controller {
  static targets = ["tbody", "addBtn"]

  // ===== ADD VARIANT =====

  addVariant() {
    const btn = this.addBtnTarget
    const tbody = this.tbodyTarget
    const idx = Date.now()
    const prefix = `product[variants_attributes][${idx}]`
    const optionTypes = JSON.parse(btn.dataset.optionTypes || '[]')

    let optionsHtml = ''
    optionTypes.forEach(ot => {
      let opts = '<option value="">-- alege --</option>'
      ;(ot.values || []).forEach(ov => {
        opts += `<option value="${ov.id}">${ov.name}</option>`
      })
      optionsHtml += `<div class="variant-option-select">
        <label class="variant-option-label">${ot.name}</label>
        <select name="${prefix}[option_value_ids][]" class="variant-input">${opts}</select>
      </div>`
    })

    let statusOpts = ''
    ;['active', 'inactive'].forEach(s => {
      statusOpts += `<option value="${s}">${s.charAt(0).toUpperCase() + s.slice(1)}</option>`
    })

    const tr1 = document.createElement('tr')
    tr1.className = 'variant-row variant-row-top variant-new'
    tr1.innerHTML = `
      <input type="hidden" name="${prefix}[_destroy]" value="0" class="destroy-flag">
      <td class="variant-options-cell">${optionsHtml}</td>
      <td colspan="3">
        <label class="variant-field-label">SKU</label>
        <div style="display:flex; gap:4px; align-items:center;">
          <input type="text" name="${prefix}[sku]" placeholder="SKU-001" class="variant-input variant-sku" style="flex:1;" data-variant-id="">
          <button type="button" class="variant-sku-auto-btn" style="display:none; padding:1px 6px; font-size:11px; cursor:pointer; border:1px solid #ccc; border-radius:3px; background:#f8f9fa; white-space:nowrap;" title="Revenire la auto-generare">&#8635;</button>
        </div>
        <small class="variant-sku-status" style="display:none; margin-top:2px; font-size:11px;"></small>
      </td>
      <td colspan="2">
        <label class="variant-field-label">EAN / GTIN</label>
        <input type="text" name="${prefix}[ean]" placeholder="1234567890123" class="variant-input variant-ean" style="width:100%;">
      </td>
    `

    const tr2 = document.createElement('tr')
    tr2.className = 'variant-row variant-row-bottom variant-new'
    tr2.innerHTML = `
      <td class="variant-image-cell">
        <label class="variant-field-label">Imagine</label>
        <input type="hidden" name="${prefix}[external_image_url]" value="" class="variant-image-hidden">
        <div class="variant-images-hidden"></div>
        <div class="variant-image-gallery"></div>
        <input type="file" accept="image/*" multiple class="variant-image-input" data-action="change->product-variants#uploadVariantImages" />
        <label class="variant-add-img-btn" title="Adauga imagini" data-action="click->product-variants#triggerFileInput">+</label>
      </td>
      <td><label class="variant-field-label">Pret vanzare</label><input type="number" name="${prefix}[price]" step="0.01" min="0" placeholder="0.00" class="variant-input variant-price"></td>
      <td><label class="variant-field-label">Pret achizitie</label><input type="number" name="${prefix}[cost_price]" step="0.01" min="0" placeholder="0.00" class="variant-input variant-cost-price" style="width:70px;"></td>
      <td><label class="variant-field-label">Promo (RON)</label><input type="number" name="${prefix}[discount_price]" step="0.01" min="0" placeholder="0.00" class="variant-input variant-discount-price" style="width:70px;"><label style="display:flex;align-items:center;gap:3px;margin-top:3px;cursor:pointer;"><input type="hidden" name="${prefix}[promo_active]" value="0"><input type="checkbox" name="${prefix}[promo_active]" value="1" style="width:auto;margin:0;"><span style="font-size:10px;">Activ</span></label></td>
      <td><label class="variant-field-label">Stoc</label><input type="number" name="${prefix}[stock]" min="0" placeholder="0" value="0" class="variant-input variant-stock"></td>
      <td><label class="variant-field-label">TVA %</label><input type="number" name="${prefix}[vat_rate]" min="0" step="0.01" placeholder="0" value="0" class="variant-input variant-vat"></td>
      <td><label class="variant-field-label">Status</label><select name="${prefix}[status]" class="variant-input variant-status">${statusOpts}</select></td>
      <td><label class="variant-field-label">Sursa</label><br><span class="badge badge-new">Nou</span></td>
      <td style="white-space:nowrap;"><button type="button" class="btn btn-info btn-sm" title="Duplica varianta" style="margin-right:4px; font-size:12px;" data-action="click->product-variants#duplicateVariant">Duplica</button><button type="button" class="btn btn-danger btn-sm" title="Sterge varianta" data-action="click->product-variants#removeVariant">&times;</button></td>
    `

    const tr3 = document.createElement('tr')
    tr3.className = 'variant-row variant-row-dimensions variant-new'
    tr3.innerHTML = `
      <td colspan="10" style="padding: 6px 12px; background: #f8f9fa; border-bottom: 2px solid #dee2e6;">
        <div style="display:flex; gap:16px; align-items:center; flex-wrap:wrap;">
          <span style="font-size:12px; font-weight:600; color:#666;">Dimensiuni:</span>
          <div style="display:flex; align-items:center; gap:4px;"><label class="variant-field-label" style="margin:0; font-size:11px;">H</label><input type="number" name="${prefix}[height]" step="1" min="0" placeholder="0" class="variant-input" style="width:60px;"><span style="font-size:11px; color:#999;">mm</span></div>
          <div style="display:flex; align-items:center; gap:4px;"><label class="variant-field-label" style="margin:0; font-size:11px;">W</label><input type="number" name="${prefix}[width]" step="1" min="0" placeholder="0" class="variant-input" style="width:60px;"><span style="font-size:11px; color:#999;">mm</span></div>
          <div style="display:flex; align-items:center; gap:4px;"><label class="variant-field-label" style="margin:0; font-size:11px;">D</label><input type="number" name="${prefix}[depth]" step="1" min="0" placeholder="0" class="variant-input" style="width:60px;"><span style="font-size:11px; color:#999;">mm</span></div>
          <div style="display:flex; align-items:center; gap:4px;"><label class="variant-field-label" style="margin:0; font-size:11px;">Greutate</label><input type="number" name="${prefix}[weight]" step="1" min="0" placeholder="0" class="variant-input" style="width:70px;"><span style="font-size:11px; color:#999;">g</span></div>
        </div>
      </td>
    `

    tbody.appendChild(tr1)
    tbody.appendChild(tr2)
    tbody.appendChild(tr3)
  }

  // ===== REMOVE VARIANT =====

  removeVariant(e) {
    const bottomRow = e.target.closest('tr.variant-row-bottom')
    let topRow = bottomRow ? bottomRow.previousElementSibling : e.target.closest('tr.variant-row-top')
    if (!topRow) return
    const realBottom = bottomRow || topRow.nextElementSibling
    const dimRow = realBottom ? realBottom.nextElementSibling : null
    const hasDimRow = dimRow && dimRow.classList.contains('variant-row-dimensions')
    const idField = topRow.querySelector('input[name$="[id]"]')
    const destroyFlag = topRow.querySelector('.destroy-flag')

    if (idField && idField.value) {
      destroyFlag.value = '1'
      topRow.classList.add('variant-destroyed')
      topRow.style.display = 'none'
      if (realBottom && realBottom.classList.contains('variant-row-bottom')) {
        realBottom.classList.add('variant-destroyed')
        realBottom.style.display = 'none'
      }
      if (hasDimRow) { dimRow.classList.add('variant-destroyed'); dimRow.style.display = 'none' }
    } else {
      if (hasDimRow) dimRow.remove()
      if (realBottom && realBottom.classList.contains('variant-row-bottom')) realBottom.remove()
      topRow.remove()
    }
  }

  // ===== DUPLICATE VARIANT =====

  duplicateVariant(e) {
    const bottomRow = e.target.closest('tr.variant-row-bottom')
    if (!bottomRow) return
    const topRow = bottomRow.previousElementSibling
    const dimRow = bottomRow.nextElementSibling
    if (!topRow || !topRow.classList.contains('variant-row-top')) return

    this.addVariant()

    const allRows = this.tbodyTarget.querySelectorAll('tr.variant-row')
    const newRows = []
    for (let i = allRows.length - 1; i >= 0 && newRows.length < 3; i--) newRows.unshift(allRows[i])
    const [newTop, newBottom, newDim] = newRows
    if (!newTop || !newBottom) return

    // Copy options
    const srcSelects = topRow.querySelectorAll('select[name*="option_value_ids"]')
    const dstSelects = newTop.querySelectorAll('select[name*="option_value_ids"]')
    srcSelects.forEach((src, i) => { if (dstSelects[i]) dstSelects[i].value = src.value })

    // Copy price fields
    ;['price', 'cost_price', 'discount_price', 'stock', 'vat_rate'].forEach(field => {
      const src = bottomRow.querySelector(`input[name*="[${field}]"]`)
      const dst = newBottom.querySelector(`input[name*="[${field}]"]`)
      if (src && dst) dst.value = src.value
    })

    // Copy promo checkbox + status
    const srcPromo = bottomRow.querySelector('input[type="checkbox"][name*="[promo_active]"]')
    const dstPromo = newBottom.querySelector('input[type="checkbox"][name*="[promo_active]"]')
    if (srcPromo && dstPromo) dstPromo.checked = srcPromo.checked
    const srcStatus = bottomRow.querySelector('select[name*="[status]"]')
    const dstStatus = newBottom.querySelector('select[name*="[status]"]')
    if (srcStatus && dstStatus) dstStatus.value = srcStatus.value

    // Copy dimensions
    if (dimRow && dimRow.classList.contains('variant-row-dimensions') && newDim) {
      ;['height', 'width', 'depth', 'weight'].forEach(field => {
        const src = dimRow.querySelector(`input[name*="[${field}]"]`)
        const dst = newDim.querySelector(`input[name*="[${field}]"]`)
        if (src && dst) dst.value = src.value
      })
    }

    // Clear SKU and EAN (must be unique)
    const newSkuInput = newTop.querySelector('input.variant-sku')
    if (newSkuInput) newSkuInput.value = ''
    const newEanInput = newTop.querySelector('input[name*="[ean]"]')
    if (newEanInput) newEanInput.value = ''
  }

  // ===== VARIANT IMAGE UPLOAD =====

  triggerFileInput(e) {
    const td = e.target.closest('.variant-image-cell')
    const fileInput = td.querySelector('.variant-image-input')
    if (fileInput) fileInput.click()
  }

  async uploadVariantImages(e) {
    const files = e.target.files
    if (!files.length) return
    const td = e.target.closest('.variant-image-cell')
    const mainHidden = td.querySelector('.variant-image-hidden')
    const gallery = td.querySelector('.variant-image-gallery')
    const hiddenContainer = td.querySelector('.variant-images-hidden')
    const baseName = mainHidden.name.replace('[external_image_url]', '[external_image_urls][]')

    for (const file of files) {
      try {
        const uniqueName = Date.now() + '_' + encodeURIComponent(file.name)
        const res = await fetch('/uploads/presign?filename=' + uniqueName)
        const { upload_url, headers } = await res.json()
        const upload = await fetch(upload_url, {
          method: 'PUT',
          headers: { 'Content-Type': headers['Content-Type'], 'AccessKey': headers['AccessKey'] },
          body: file
        })

        if (upload.ok) {
          const path = new URL(upload_url).pathname.split('/').slice(2).join('/')
          const cdnUrl = 'https://ayus-cdn.b-cdn.net/' + path

          if (!mainHidden.value) {
            mainHidden.value = cdnUrl
            const item = document.createElement('div')
            item.className = 'variant-gallery-item'
            item.dataset.role = 'main'
            item.innerHTML = `<img src="${cdnUrl}" class="variant-thumb"><button type="button" class="remove-btn" data-role="main" data-action="click->product-variants#removeVariantImage">\u00d7</button><span class="variant-img-label">P</span>`
            gallery.appendChild(item)
          } else {
            const hidden = document.createElement('input')
            hidden.type = 'hidden'
            hidden.name = baseName
            hidden.value = cdnUrl
            hiddenContainer.appendChild(hidden)
            const item = document.createElement('div')
            item.className = 'variant-gallery-item'
            item.dataset.role = 'secondary'
            item.dataset.url = cdnUrl
            item.innerHTML = `<img src="${cdnUrl}" class="variant-thumb"><button type="button" class="remove-btn" data-role="secondary" data-action="click->product-variants#removeVariantImage">\u00d7</button>`
            gallery.appendChild(item)
          }
        }
      } catch (err) {}
    }
    e.target.value = ''
  }

  removeVariantImage(e) {
    const item = e.target.closest('.variant-gallery-item')
    const td = e.target.closest('.variant-image-cell')
    const role = e.target.dataset.role

    if (role === 'main') {
      td.querySelector('.variant-image-hidden').value = ''
      item.remove()
      const firstSecondary = td.querySelector('.variant-gallery-item[data-role="secondary"]')
      if (firstSecondary) {
        const url = firstSecondary.dataset.url
        td.querySelector('.variant-image-hidden').value = url
        firstSecondary.dataset.role = 'main'
        firstSecondary.innerHTML = `<img src="${url}" class="variant-thumb"><button type="button" class="remove-btn" data-role="main" data-action="click->product-variants#removeVariantImage">\u00d7</button><span class="variant-img-label">P</span>`
        const hiddens = td.querySelector('.variant-images-hidden').querySelectorAll('input[type="hidden"]')
        hiddens.forEach(h => { if (h.value === url) h.remove() })
      }
    } else {
      const url = item.dataset.url
      td.querySelector('.variant-images-hidden').querySelectorAll('input[type="hidden"]').forEach(h => { if (h.value === url) h.remove() })
      item.remove()
    }
  }
}
