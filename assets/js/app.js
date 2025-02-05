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
}

const liveSocket = new LiveSocket(livePath, Socket, {
  transport: liveTran === "longpoll" ? LongPoll : WebSocket,
  params: { _csrf_token: csrfToken },
  hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// window.liveSocket = liveSocket

