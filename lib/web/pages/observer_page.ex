defmodule Observer.Web.ObserverPage do
  @moduledoc """
  This is the live component responsible for handling the Observer page
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Page

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white text-black">
      <div class="flex items-center">
        <div
          id="live-observer-alert"
          class="p-2 border-l-8 border-yellow-400 rounded-l-lg bg-gray-300 text-yellow-600"
          role="alert"
        >
          <div class="flex items-center">
            <div class="flex items-center py-8">
              <svg
                class="flex-shrink-0 w-4 h-4 me-2"
                aria-hidden="true"
                xmlns="http://www.w3.org/2000/svg"
                fill="currentColor"
                viewBox="0 0 20 20"
              >
                <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5ZM9.5 4a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM12 15H8a1 1 0 0 1 0-2h1v-3H8a1 1 0 0 1 0-2h2a1 1 0 0 1 1 1v4h1a1 1 0 0 1 0 2Z" />
              </svg>
              <span class="sr-only">Info</span>
              <h3 class="text-sm font-medium">Attention</h3>
            </div>
            <div class="ml-2 mr-2 mt-2 mb-2 text-xs text-red-500">
              Incorrect use of the <b>:dbg</b>
              tracer in production can lead to performance degradation, latency and crashes.
              <b>DeployEx Live observer</b>
              enforces limits on the maximum number of messages and applies a timeout (in seconds)
              to ensure the debugger doesn't remain active unintentionally. Check out the
              <a
                href="https://www.erlang.org/docs/24/man/dbg"
                class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
              >
                Erlang Debugger
              </a>
              for more detailed information.
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) do
    socket
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Live Observer")
  end

  @impl Page
  def handle_parent_event(_message, _value, socket) do
    {:noreply, socket}
  end

  @impl Page
  def handle_info(_message, socket) do
    {:noreply, socket}
  end
end
