// Phoenix assets are imported from dependencies
import topbar from "topbar"

import { loadAll } from "./lib/settings";

import LiveMetricsEChart from "./hooks/live_metrics_echart";
import ObserverEChart from "./hooks/observer_echart";
import ScrollBottom from "./hooks/scroll_bottom";
import Themer from "./hooks/themer";
import AutoDismissFlash from "./hooks/auto_dismiss_flash";

const hooks = {
  LiveMetricsEChart,
  ObserverEChart,
  ScrollBottom,
  Themer,
  AutoDismissFlash,
};

// Topbar ---

let topBarScheduled = undefined;

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })

window.addEventListener("phx:page-loading-start", (info) => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 500);
  }
});

window.addEventListener("phx:page-loading-stop", (info) => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
});

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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveTran = document.querySelector("meta[name='live-transport']").getAttribute("content")
const livePath = document.querySelector("meta[name='live-path']").getAttribute("content")

const liveSocket = new LiveView.LiveSocket(livePath, Phoenix.Socket, {
  transport: liveTran === "longpoll" ? Phoenix.LongPoll : WebSocket,
  params: { _csrf_token: csrfToken, init_state: loadAll() },
  hooks
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// window.liveSocket = liveSocket

