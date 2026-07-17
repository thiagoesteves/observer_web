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
            <Core.input
              field={@form[:refresh_seconds]}
              type="select"
              label="Refresh"
              options={[{"Paused", "0"}, {"2s", "2"}, {"5s", "5"}, {"10s", "10"}]}
            />
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

        <div
          :if={@os_data == :os_mon_not_started}
          class="p-4 mb-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Operating system data (load averages, CPU, OS memory and disks) requires the
          <span class="font-mono font-semibold">:os_mon</span>
          application on the selected service. Add
          <span class="font-mono font-semibold">:os_mon</span>
          to your <span class="font-mono font-semibold">extra_applications</span>
          to enable it.
        </div>

        <div :if={is_map(@os_data)} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded mb-4">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Operating System
          </h2>

          <div class="flex flex-wrap gap-2 px-4 py-2 text-xs">
            <span
              :if={@os_data.os}
              class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700"
            >
              OS: {@os_data.os}
            </span>
            <span
              :for={
                {label, value} <-
                  if(@os_data.load,
                    do: [
                      {"Load 1m", @os_data.load.avg1},
                      {"Load 5m", @os_data.load.avg5},
                      {"Load 15m", @os_data.load.avg15}
                    ],
                    else: []
                  )
              }
              class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700"
            >
              {label}: {value}
            </span>
          </div>

          <div :if={@os_data.memory} class="px-4 pb-2 text-xs text-gray-700 dark:text-gray-200">
            <div class="flex items-center gap-2">
              <span class="font-semibold">OS Memory</span>
              <div class="w-40 h-2 rounded bg-gray-200 dark:bg-gray-600 overflow-hidden">
                <div
                  class={["h-2 rounded", usage_color(@os_data.memory.used_percent)]}
                  style={"width: #{min(@os_data.memory.used_percent, 100)}%"}
                />
              </div>
              <span>
                {@os_data.memory.used_percent}% of {format_bytes(@os_data.memory.total_bytes)} used ({format_bytes(
                  @os_data.memory.available_bytes
                )} available)
              </span>
            </div>
          </div>

          <Core.table_tracing :if={@os_data.cpus != []} id="system-os-cpus" rows={@os_data.cpus}>
            <:col :let={cpu} label="CPU">{cpu.id}</:col>
            <:col :let={cpu} label="UTILIZATION">
              <div class="flex items-center gap-2">
                <div class="w-40 h-2 rounded bg-gray-200 dark:bg-gray-600 overflow-hidden">
                  <div
                    class={["h-2 rounded", usage_color(cpu.busy_percent)]}
                    style={"width: #{min(cpu.busy_percent, 100)}%"}
                  />
                </div>
                <span>{cpu.busy_percent}%</span>
              </div>
            </:col>
          </Core.table_tracing>

          <Core.table_tracing :if={@os_data.disks != []} id="system-os-disks" rows={@os_data.disks}>
            <:col :let={disk} label="DISK">{disk.mount}</:col>
            <:col :let={disk} label="SIZE">{format_bytes(disk.total_kbytes * 1_024)}</:col>
            <:col :let={disk} label="USED">
              <div class="flex items-center gap-2">
                <div class="w-40 h-2 rounded bg-gray-200 dark:bg-gray-600 overflow-hidden">
                  <div
                    class={["h-2 rounded", usage_color(disk.capacity_percent)]}
                    style={"width: #{min(disk.capacity_percent, 100)}%"}
                  />
                </div>
                <span>{disk.capacity_percent}%</span>
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

    socket
    |> assign_defaults()
    |> restart_tick_chain()
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
    |> assign(:os_data, nil)
    |> assign(:snapshot_error, nil)
    |> assign(:tick_gen, 0)
    |> assign(
      :form,
      to_form(%{"service" => to_string(Node.self()), "refresh_seconds" => "5"})
    )
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
    {:noreply,
     socket
     |> assign(:form, to_form(params))
     |> restart_tick_chain()}
  end

  def handle_parent_event("system-refresh", _params, socket) do
    {:noreply, restart_tick_chain(socket)}
  end

  # Refresh ticks carry a generation counter (same pattern as the Network and Logs pillars):
  # changing any control bumps the generation and starts a new timer chain, so a tick from a
  # cancelled chain that was already in flight is ignored instead of spawning a second chain.
  defp restart_tick_chain(socket) do
    tick_gen = socket.assigns.tick_gen + 1
    send(self(), {:system_tick, tick_gen})

    assign(socket, :tick_gen, tick_gen)
  end

  @impl Page
  def handle_info({:system_tick, gen}, %{assigns: %{tick_gen: gen}} = socket) do
    node = selected_service(socket)

    socket =
      case SystemInfo.node_info(node) do
        {:ok, node_info} ->
          socket
          |> assign(:node_info, node_info)
          |> assign(:limits, SystemInfo.limits(node))
          |> assign(:allocators, SystemInfo.allocators(node))
          |> assign(:os_data, fetch_os_data(node))
          |> assign(:snapshot_error, nil)

        {:error, reason} ->
          assign(socket, :snapshot_error, reason)
      end

    refresh_seconds = positive_int(socket.assigns.form.params["refresh_seconds"], 0)

    if refresh_seconds > 0 do
      Process.send_after(self(), {:system_tick, gen}, refresh_seconds * 1_000)
    end

    {:noreply, socket}
  end

  def handle_info({:system_tick, _stale_gen}, socket) do
    {:noreply, socket}
  end

  def handle_info({:nodeup, _node}, socket) do
    {:noreply, assign(socket, :services, services())}
  end

  def handle_info({:nodedown, node}, %{assigns: %{form: form}} = socket) do
    socket = assign(socket, :services, services())

    if to_string(node) == form.params["service"] do
      {:noreply,
       socket
       |> assign(:form, to_form(Map.put(form.params, "service", to_string(Node.self()))))
       |> restart_tick_chain()}
    else
      {:noreply, socket}
    end
  end

  defp positive_int(value, default) do
    case Integer.parse(value || "") do
      {int, ""} when int >= 0 -> int
      _invalid -> default
    end
  end

  defp fetch_os_data(node) do
    case SystemInfo.os_data(node) do
      {:ok, os_data} -> os_data
      {:error, :os_mon_not_started} -> :os_mon_not_started
      {:error, _reason} -> nil
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
    VM limits, memory allocator carrier utilization (low utilization on a busy allocator is a
    sign of fragmentation) and operating system data when :os_mon is running. The snapshot
    refreshes automatically at the selected interval - press REFRESH to update immediately, or
    pause the interval.
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
