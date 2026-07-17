defmodule Observer.Web.Page do
  @moduledoc """
  Behaviour for dashboard pages, both the built-in pillars and custom pages provided by the
  host application.

  A page is a `Phoenix.LiveComponent` that additionally implements this behaviour: the parent
  `Observer.Web.IndexLive` LiveView forwards its mount, params, info and event callbacks to the
  page currently being displayed.

  ## Building a custom page

  `use Observer.Web.Page` pulls in `Phoenix.LiveComponent` and provides overridable default
  implementations for every callback, so a minimal page only needs `render/1`:

  ```elixir
  defmodule MyApp.ObserverQueuePage do
    use Observer.Web.Page

    @impl Phoenix.LiveComponent
    def render(assigns) do
      ~H\"\"\"
      <div class="min-h-screen bg-white dark:bg-gray-800 p-4">
        Queue length: {@queue_length}
      </div>
      \"\"\"
    end

    @impl Observer.Web.Page
    def handle_mount(socket) do
      Phoenix.Component.assign(socket, :queue_length, MyApp.Queue.length())
    end
  end
  ```

  Register the page under a route name when mounting the dashboard:

  ```elixir
  observer_dashboard "/observer", pages: [queue: MyApp.ObserverQueuePage]
  ```

  The page shows up in the navigation bar as `QUEUE` and is served at
  `/observer/queue`. Within the component, the standard dashboard assigns are available:
  `@access` (`:all` or `:read_only`), `@user`, `@params`, `@theme` and `@page`.

  ## Callback flow

  * `c:handle_mount/1` - called from the parent LiveView on mount and before page changes.
  * `c:handle_params/3` - called on every `c:Phoenix.LiveView.handle_params/3`.
  * `c:handle_info/2` - called for any message the parent LiveView does not handle itself.
  * `c:handle_parent_event/3` - called for any `phx-` event the parent does not handle itself.
  """

  alias Phoenix.LiveView.Socket

  @doc """
  Called from parent live view on mount and before page changes.
  """
  @callback handle_mount(socket :: Socket.t()) :: Socket.t()

  @doc """
  Called by parent live view on param changes.
  """
  @callback handle_params(params :: map(), uri :: String.t(), socket :: Socket.t()) ::
              {:noreply, Socket.t()}

  @doc """
  Called by parent live view on info messages.
  """
  @callback handle_info(message :: term(), socket :: Socket.t()) :: {:noreply, Socket.t()}

  @doc """
  Called by parent live view on handle_event messages.
  """
  @callback handle_parent_event(message :: term(), value :: term(), socket :: Socket.t()) ::
              {:noreply, Socket.t()}

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Phoenix.LiveComponent

      @behaviour Observer.Web.Page

      @impl Observer.Web.Page
      def handle_mount(socket), do: socket

      @impl Observer.Web.Page
      def handle_params(_params, _uri, socket), do: {:noreply, socket}

      @impl Observer.Web.Page
      def handle_info(_message, socket), do: {:noreply, socket}

      @impl Observer.Web.Page
      def handle_parent_event(_event, _value, socket), do: {:noreply, socket}

      defoverridable handle_mount: 1, handle_params: 3, handle_info: 2, handle_parent_event: 3
    end
  end
end
