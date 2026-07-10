// Priority navigation: tabs that don't fit the available width are moved into a "MORE"
// dropdown instead of wrapping or widening the page. Re-measures on every resize.
const NavOverflow = {
  mounted() {
    this.bar = this.el.querySelector("[data-nav-items]")
    this.moreButton = this.el.querySelector("[data-nav-more]")
    this.panel = this.el.querySelector("[data-nav-panel]")
    this.items = Array.from(this.bar.children).filter((el) => el !== this.moreButton)

    this.onMoreClick = (event) => {
      event.stopPropagation()
      this.panel.hidden = !this.panel.hidden
    }
    this.moreButton.addEventListener("click", this.onMoreClick)

    this.onDocumentClick = (event) => {
      if (!this.el.contains(event.target)) this.panel.hidden = true
    }
    document.addEventListener("click", this.onDocumentClick)

    this.resizeObserver = new ResizeObserver(() => this.measure())
    this.resizeObserver.observe(this.el)
    this.measure()
  },

  destroyed() {
    document.removeEventListener("click", this.onDocumentClick)
    if (this.resizeObserver) this.resizeObserver.disconnect()
  },

  measure() {
    const gap = 4 // matches the bar's gap-1

    // Reset: everything back on the bar, then decide what overflows
    this.items.forEach((item) => this.bar.insertBefore(item, this.moreButton))
    this.moreButton.hidden = true

    const fullWidth = this.bar.clientWidth
    const itemWidths = this.items.map((item) => item.offsetWidth)
    const totalWidth = itemWidths.reduce((acc, width, i) => acc + width + (i > 0 ? gap : 0), 0)

    if (totalWidth <= fullWidth) {
      this.panel.hidden = true
      return
    }

    // Not everything fits: reserve room for the MORE button, keep what fits, move the rest
    this.moreButton.hidden = false
    const available = fullWidth - this.moreButton.offsetWidth - gap

    let used = 0
    this.items.forEach((item, i) => {
      used += itemWidths[i] + (i > 0 ? gap : 0)
      if (used > available) this.panel.appendChild(item)
    })
  },
}

export default NavOverflow
