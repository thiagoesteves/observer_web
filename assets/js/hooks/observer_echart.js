import * as echarts from "echarts"

const ObserverEChart = {
  mounted() {
    selector = "#" + this.el.id

    this.chart = echarts.init(this.el.querySelector(selector + "-chart"))
    option = JSON.parse(this.el.querySelector(selector + "-data").textContent)

    this.chart.setOption(option)
  },
  updated() {
    selector = "#" + this.el.id
    // This flag will indicate to Echart to not merge the data
    let notMerge = !this.el.dataset.merge ?? true;

    newOption = JSON.parse(this.el.querySelector(selector + "-data").textContent)

    // Compare the new option series with the previous one
    if (this.previousSeries && JSON.stringify(this.previousSeries) === JSON.stringify(newOption.series)) {
      // If the data is the same, skip the update
      // console.log('[ObserverEChart] No changes in the data, skipping setOption');
      return;  // Exit without updating the chart
    }

    // Save the new option as the previous one for future comparisons
    this.previousSeries = newOption.series;

    // Set the callback in the tooltip formatter (or any other part of the option)
    var callback = (args) => {
      this.pushEventTo(this.el, "request-process", { id: args.data.id, series_name: args.seriesName });
      return args.data.id;
    }

    newOption.tooltip = {
      formatter: callback
    };

    this.chart.setOption(newOption, notMerge)
  }
};

export default ObserverEChart