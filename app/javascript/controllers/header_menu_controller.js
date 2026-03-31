import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hamburger", "closeBtn", "navWrapper", "accountToggle", "accountDropdown"]

  connect() {
    this.setupMobileMenu()
    this.setupAccountDropdown()
  }

  // ===== MOBILE MENU =====

  setupMobileMenu() {
    if (!this.hasHamburgerTarget || !this.hasCloseBtnTarget || !this.hasNavWrapperTarget) return

    this.hamburgerTarget.setAttribute('aria-label', 'Deschide meniul')
    this.closeBtnTarget.setAttribute('aria-label', 'Inchide meniul')
    this.navWrapperTarget.setAttribute('aria-hidden', 'true')
  }

  toggleMenu() {
    if (!this.hasNavWrapperTarget) return
    const isOpen = this.navWrapperTarget.classList.contains('active')

    if (isOpen) {
      this.closeMenu()
    } else {
      this.openMenu()
    }
  }

  openMenu() {
    if (!this.hasNavWrapperTarget) return
    this.navWrapperTarget.classList.add('active')
    this.navWrapperTarget.setAttribute('aria-hidden', 'false')
    if (this.hasHamburgerTarget) this.hamburgerTarget.setAttribute('aria-expanded', 'true')
    document.body.style.overflow = 'hidden'
  }

  closeMenu() {
    if (!this.hasNavWrapperTarget) return
    this.navWrapperTarget.classList.remove('active')
    this.navWrapperTarget.setAttribute('aria-hidden', 'true')
    if (this.hasHamburgerTarget) this.hamburgerTarget.setAttribute('aria-expanded', 'false')
    document.body.style.overflow = ''
  }

  closeMenuOnClickOutside(e) {
    if (!this.hasNavWrapperTarget) return
    if (!this.navWrapperTarget.contains(e.target) &&
        (!this.hasHamburgerTarget || !this.hamburgerTarget.contains(e.target))) {
      this.closeMenu()
    }
  }

  closeMenuOnEscape(e) {
    if (e.key === 'Escape') this.closeMenu()
  }

  // ===== ACCOUNT DROPDOWN =====

  setupAccountDropdown() {
    // No setup needed - actions handle everything
  }

  toggleAccount(e) {
    e.preventDefault()
    e.stopPropagation()
    if (!this.hasAccountDropdownTarget) return
    this.accountDropdownTarget.classList.toggle('show')
  }

  closeAccountOnClickOutside(e) {
    if (!this.hasAccountDropdownTarget || !this.hasAccountToggleTarget) return
    if (!this.accountToggleTarget.contains(e.target) && !this.accountDropdownTarget.contains(e.target)) {
      this.accountDropdownTarget.classList.remove('show')
    }
  }

  closeAccountOnEscape(e) {
    if (!this.hasAccountDropdownTarget) return
    if (e.key === 'Escape') this.accountDropdownTarget.classList.remove('show')
  }
}
