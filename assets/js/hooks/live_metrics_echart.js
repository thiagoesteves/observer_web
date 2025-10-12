import * as echarts from "echarts"

const LiveMetricsEChart = {
  mounted() {
    selector = "#" + this.el.id

    const dataConfig = JSON.parse(this.el.dataset.config)
    const columns = JSON.parse(this.el.dataset.columns)

    this.chart = echarts.init(this.el.querySelector(selector + "-chart"))
    this.chart.setOption(dataConfig)
    this.graph_cols = columns
  },
  updated() {
    const dataConfig = JSON.parse(this.el.dataset.config)
    const reset = JSON.parse(this.el.dataset.reset)
    const columns = JSON.parse(this.el.dataset.columns)

    if (reset) {
      this.chart.setOption(dataConfig)

    } else {
      var option = this.chart.getOption();
      var updatedXAxis = option.xAxis[0].data.concat(dataConfig.xAxis.data);
      var updatedSeries = option.series.map((series, index) => {
        // Concatenate the corresponding dataset to each series
        return {
          data: series.data.concat(dataConfig.series[index] ? dataConfig.series[index].data : [])
        };
      });

      this.chart.setOption(
        {
          xAxis: { data: updatedXAxis },
          series: updatedSeries
        })
    }
    if (columns != this.columns) {
      this.chart.resize()
      this.columns = columns
    }
  }
};

export default LiveMetricsEChart