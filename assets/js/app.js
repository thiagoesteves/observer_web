// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket, LongPoll } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "topbar"
import * as echarts from "echarts"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveTran = document.querySelector("meta[name='live-transport']").getAttribute("content")
const livePath = document.querySelector("meta[name='live-path']").getAttribute("content")

let hooks = {}

hooks.ScrollBottom = {
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

hooks.ObserverEChart = {
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
      console.log('No changes in the data, skipping setOption');
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

hooks.LiveMetricsEChart = {
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

const liveSocket = new LiveSocket(livePath, Socket, {
  transport: liveTran === "longpoll" ? LongPoll : WebSocket,
  params: { _csrf_token: csrfToken },
  hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:copy_to_clipboard", event => {
  if ("clipboard" in navigator) {
    const text = event.detail.text;
    navigator.clipboard.writeText(text);
  } else {
    alert("Sorry, your browser does not support clipboard copy.");
  }

  const defaultMessage = document.getElementById("default-message-" + event.detail.id);
  if (defaultMessage) {
    defaultMessage.setAttribute("hidden", "");
  }

  const successMessage = document.getElementById("success-message-" + event.detail.id);
  if (successMessage) {
    successMessage.removeAttribute("hidden");
  }

  setTimeout(() => {
    const successMessage = document.getElementById("success-message-" + event.detail.id);
    if (successMessage) {
      successMessage.setAttribute("hidden", "");
    }

    const defaultMessage = document.getElementById("default-message-" + event.detail.id);
    if (defaultMessage) {
      defaultMessage.removeAttribute("hidden");
    }
  }, 1000);
});

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// window.liveSocket = liveSocket

