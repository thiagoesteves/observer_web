const AutoDismissFlash = {
  mounted() {
    setTimeout(() => {
      this.el.style.transition = "opacity 0.5s";
      this.el.style.opacity = "0";
      setTimeout(() => this.pushEventTo(this.el, "clear-flash"), 500);
    }, 3500);
  },
};

export default AutoDismissFlash
