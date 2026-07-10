defmodule Observer.Web.System.Page do
  @moduledoc """
  This is the live component responsible for the System pillar: a read-only snapshot of a
  selected node's runtime information, resource counts against their VM limits, and per-allocator
  carrier utilization - the web equivalent of the observer GUI's System and Memory Allocators
  tabs.
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Page
  alias ObserverWeb.SystemInfo

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="system"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={attention_msg()}
      >
        <:inner_form>
          <.form
            for={@form}
            id="system-update-form"
            class="flex flex-col md:flex-row md:items-end shrink-0 ml-2 mr-2 py-2 text-xs text-center text-zinc-800 dark:text-white whitespace-nowrap gap-x-5 gap-y-1"
            phx-change="form-update"
          >
            <Core.input field={@form[:service]} type="select" label="Service" options={@services} />
          </.form>
        </:inner_form>
        <:inner_button>
          <button
            id="system-refresh"
            phx-click="system-refresh"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 dark:bg-green-700 transform active:scale-75 transition-transform hover:bg-green-800 dark:hover:bg-green-800 self-stretch w-40 xl:w-64 flex items-center justify-center text-sm font-semibold text-white active:text-white/80"
          >
            REFRESH
          </button>
        </:inner_button>
      </Attention.content>

      <div class="p-2">
        <div :if={@snapshot_error} class="p-4 text-sm text-red-500 dark:text-red-300">
          Could not read {@form.params["service"]}: {inspect(@snapshot_error)}
        </div>

        <div
          :if={@node_info == nil and @snapshot_error == nil}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Collecting system information...
        </div>

        <div :if={@node_info} class="flex flex-wrap gap-2 px-2 pb-2 text-xs">
          <span
            :for={
              {label, value} <- [
                {"OTP", @node_info.otp_release},
                {"ERTS", @node_info.erts_version},
                {"Architecture", @node_info.system_architecture},
                {"Schedulers", "#{@node_info.schedulers_online}/#{@node_info.schedulers}"},
                {"Uptime", format_uptime(@node_info.uptime_ms)}
              ]
            }
            class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700"
          >
            {label}: {value}
          </span>
        </div>

        <div :if={@limits != []} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded mb-4">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Limits
          </h2>
          <Core.table_tracing id="system-limits" rows={@limits}>
            <:col :let={limit} label="RESOURCE">{limit.name}</:col>
            <:col :let={limit} label="COUNT">{limit.count}</:col>
            <:col :let={limit} label="LIMIT">{limit.limit}</:col>
            <:col :let={limit} label="USED">
              <div class="flex items-center gap-2">
                <div class="w-40 h-2 rounded bg-gray-200 dark:bg-gray-600 overflow-hidden">
                  <div
                    class={["h-2 rounded", usage_color(limit.percent)]}
                    style={"width: #{min(limit.percent, 100)}%"}
                  />
                </div>
                <span>{limit.percent}%</span>
              </div>
            </:col>
          </Core.table_tracing>
        </div>

        <div :if={@allocators != []} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Memory Allocators
          </h2>
          <Core.table_tracing id="system-allocators" rows={@allocators}>
            <:col :let={alloc} label="ALLOCATOR">{alloc.name}</:col>
            <:col :let={alloc} label="BLOCKS SIZE">{format_bytes(alloc.blocks_size)}</:col>
            <:col :let={alloc} label="CARRIERS SIZE">{format_bytes(alloc.carriers_size)}</:col>
            <:col :let={alloc} label="UTILIZATION">
              <span :if={alloc.utilization_percent}>{alloc.utilization_percent}%</span>
              <span :if={alloc.utilization_percent == nil}>-</span>
            </:col>
          </Core.table_tracing>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) when is_connected?(socket) do
    :net_kernel.monitor_nodes(true)

    send(self(), :system_refresh)

    assign_defaults(socket)
  end

  def handle_mount(socket) do
    assign_defaults(socket)
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:services, services())
    |> assign(:node_info, nil)
    |> assign(:limits, [])
    |> assign(:allocators, [])
    |> assign(:snapshot_error, nil)
    |> assign(:form, to_form(%{"service" => to_string(Node.self())}))
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "System")
  end

  @impl Page
  def handle_parent_event("form-update", params, socket) do
    send(self(), :system_refresh)

    {:noreply, assign(socket, :form, to_form(params))}
  end

  def handle_parent_event("system-refresh", _params, socket) do
    send(self(), :system_refresh)

    {:noreply, socket}
  end

  @impl Page
  def handle_info(:system_refresh, socket) do
    node = selected_service(socket)

    case SystemInfo.node_info(node) do
      {:ok, node_info} ->
        {:noreply,
         socket
         |> assign(:node_info, node_info)
         |> assign(:limits, SystemInfo.limits(node))
         |> assign(:allocators, SystemInfo.allocators(node))
         |> assign(:snapshot_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :snapshot_error, reason)}
    end
  end

  def handle_info({:nodeup, _node}, socket) do
    {:noreply, assign(socket, :services, services())}
  end

  def handle_info({:nodedown, node}, %{assigns: %{form: form}} = socket) do
    socket = assign(socket, :services, services())

    if to_string(node) == form.params["service"] do
      send(self(), :system_refresh)

      {:noreply, assign(socket, :form, to_form(%{"service" => to_string(Node.self())}))}
    else
      {:noreply, socket}
    end
  end

  defp services do
    Enum.map([Node.self() | Node.list()], &{&1, to_string(&1)})
  end

  # The form's service value only becomes a node if it matches a currently known node - a
  # crafted payload (or a node that just left the cluster) safely falls back to the local one.
  defp selected_service(socket) do
    service = socket.assigns.form.params["service"]

    [Node.self() | Node.list()]
    |> Enum.find(Node.self(), &(to_string(&1) == service))
  end

  defp attention_msg do
    assigns = %{}

    ~H"""
    A read-only snapshot of the selected service: runtime information, resource usage against the
    VM limits and memory allocator carrier utilization (low utilization on a busy allocator is a
    sign of fragmentation). Data is collected on demand - press REFRESH to update.
    """
  end

  defp usage_color(percent) when percent >= 90, do: "bg-red-500"
  defp usage_color(percent) when percent >= 70, do: "bg-yellow-500"
  defp usage_color(_percent), do: "bg-green-500"

  defp format_uptime(ms) do
    seconds = div(ms, 1_000)
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3_600)
    minutes = div(rem(seconds, 3_600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m #{rem(seconds, 60)}s"
    end
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_024, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"
end
