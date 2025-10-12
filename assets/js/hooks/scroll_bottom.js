const ScrollBottom = {
  mounted() {
    this.el.scrollTo(0, this.el.scrollHeight);
  },

  updated() {
    const pixelsBelowBottom =
      this.el.scrollHeight - this.el.clientHeight - this.el.scrollTop;

    if (pixelsBelowBottom < this.el.clientHeight * 0.3) {
      this.el.scrollTo(0, this.el.scrollHeight);
    }
  },
};

export default ScrollBottom
