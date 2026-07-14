import * as echarts from "echarts"

// Hovering fires the tooltip formatter on every mousemove, so wait for the
// pointer to settle on a node before requesting its details from the server.
const TOOLTIP_DEBOUNCE_MS = 200

const ObserverEChart = {
  mounted() {
    const selector = "#" + this.el.id

    this.chart = echarts.init(this.el.querySelector(selector + "-chart"))
    const option = JSON.parse(this.el.querySelector(selector + "-data").textContent)

    this.setChartOption(option)
  },
  updated() {
    const selector = "#" + this.el.id
    // This flag will indicate to Echart to not merge the data
    const notMerge = !this.el.dataset.merge ?? true

    const newOption = JSON.parse(this.el.querySelector(selector + "-data").textContent)

    // Compare the new option series with the previous one
    if (this.previousSeries && JSON.stringify(this.previousSeries) === JSON.stringify(newOption.series)) {
      // If the data is the same, skip the update
      return
    }

    // Save the new option as the previous one for future comparisons
    this.previousSeries = newOption.series

    this.setChartOption(newOption, notMerge)
  },
  destroyed() {
    clearTimeout(this.tooltipTimer)
  },
  setChartOption(option, notMerge) {
    const formatter = (args) => {
      const id = args.data.id
      const seriesName = args.seriesName

      clearTimeout(this.tooltipTimer)
      this.tooltipTimer = setTimeout(() => {
        this.pushEventTo(this.el, "request-process", { id: id, series_name: seriesName })
      }, TOOLTIP_DEBOUNCE_MS)

      return id
    }

    option.tooltip = { ...option.tooltip, formatter: formatter }

    this.chart.setOption(option, notMerge)
  }
};

export default ObserverEChart
