defmodule Observer.Web.Network.Page do
  @moduledoc """
  This is the live component responsible for the Network pillar: the busiest inet ports on a
  selected node, ranked by received/sent bytes per refresh interval (deltas between samples,
  cumulative on the first tick), plus the NIF-based `socket` module sockets that port listings
  miss. A drill-down panel shows the selected port's full inet options.

  Refresh ticks carry a generation counter: changing any control bumps the generation and starts
  a new timer chain, so a tick from a cancelled chain that was already in flight is ignored
  instead of spawning a second chain.
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Page
  alias ObserverWeb.Network

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="network"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={attention_msg()}
      >
        <:inner_form>
          <.form
            for={@form}
            id="network-update-form"
            class="flex flex-col md:flex-row md:items-end shrink-0 ml-2 mr-2 py-2 text-xs text-center text-zinc-800 dark:text-white whitespace-nowrap gap-x-5 gap-y-1"
            phx-change="form-update"
          >
            <Core.input field={@form[:service]} type="select" label="Service" options={@services} />

            <Core.input
              field={@form[:sort_by]}
              type="select"
              label="Sort by"
              options={[
                {"Recv (Δ)", "recv"},
                {"Sent (Δ)", "send"},
                {"Recv + Sent (Δ)", "total"}
              ]}
            />

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
            id="network-refresh"
            phx-click="network-refresh"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 dark:bg-green-700 transform active:scale-75 transition-transform hover:bg-green-800 dark:hover:bg-green-800 self-stretch w-40 xl:w-64 flex items-center justify-center text-sm font-semibold text-white active:text-white/80"
          >
            REFRESH
          </button>
        </:inner_button>
      </Attention.content>

      <div class="p-2">
        <div :if={@sample_error} class="p-4 text-sm text-red-500 dark:text-red-300">
          Could not sample {@form.params["service"]}: {inspect(@sample_error)}
        </div>

        <div
          :if={@rows == nil and @sample_error == nil}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Collecting network endpoints...
        </div>

        <div :if={@rows != nil} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded mb-4">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Inet Ports
          </h2>
          <div :if={@rows == []} class="p-4 text-xs text-gray-500 dark:text-gray-400">
            No inet ports on this service.
          </div>
          <Core.table_tracing :if={@rows != []} id="network-results" rows={Enum.with_index(@rows)}>
            <:col :let={{row, _index}} label="PORT">{inspect(row.port)}</:col>
            <:col :let={{row, _index}} label="DRIVER">{row.name}</:col>
            <:col :let={{row, _index}} label="OWNER">
              <Core.truncated value={row.owner_label} />
            </:col>
            <:col :let={{row, _index}} label="LOCAL">{row.local}</:col>
            <:col :let={{row, _index}} label="REMOTE">{row.remote}</:col>
            <:col :let={{row, _index}} label="RECV (Δ)">{format_bytes(row.recv_diff)}</:col>
            <:col :let={{row, _index}} label="SENT (Δ)">{format_bytes(row.send_diff)}</:col>
            <:col :let={{row, _index}} label="QUEUE">{row.queue_size}</:col>
            <:col :let={{_row, index}} label="">
              <button
                id={"network-select-row-#{index}"}
                phx-click="network-select-row"
                phx-value-index={index}
                class="text-xs font-semibold text-blue-600 dark:text-blue-300 hover:underline"
              >
                DETAILS
              </button>
            </:col>
          </Core.table_tracing>
        </div>

        <div :if={@sockets != nil} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Sockets (NIF)
          </h2>
          <div :if={@sockets == []} class="p-4 text-xs text-gray-500 dark:text-gray-400">
            No `socket` module sockets on this service.
          </div>
          <Core.table_tracing :if={@sockets != []} id="network-sockets" rows={@sockets}>
            <:col :let={socket} label="ID">{socket.id_str}</:col>
            <:col :let={socket} label="KIND">{inspect(socket.kind)}</:col>
            <:col :let={socket} label="DOMAIN">{inspect(socket.domain)}</:col>
            <:col :let={socket} label="TYPE">{inspect(socket.type)}</:col>
            <:col :let={socket} label="PROTOCOL">{inspect(socket.protocol)}</:col>
            <:col :let={socket} label="READ">{format_bytes(socket.read_bytes)}</:col>
            <:col :let={socket} label="WRITE">{format_bytes(socket.write_bytes)}</:col>
          </Core.table_tracing>
        </div>

        <div
          :if={@details}
          class="mt-4 bg-white dark:bg-gray-800 w-full shadow-lg rounded border border-gray-200 dark:border-gray-600"
        >
          <div class="flex items-center justify-between px-4 pt-2">
            <h2 class="text-sm font-semibold text-gray-700 dark:text-gray-200">
              Port {inspect(@details.port)} ({@details.local} → {@details.remote})
            </h2>
            <button
              id="network-details-close"
              phx-click="network-details-close"
              class="text-xs font-semibold text-gray-500 dark:text-gray-300 hover:underline"
            >
              CLOSE
            </button>
          </div>
          <table class="w-full text-left text-xs m-2">
            <tbody>
              <tr :for={{key, value} <- details_rows(@details)} class="align-top">
                <td class="py-1 pr-4 font-semibold text-gray-700 dark:text-gray-200 whitespace-nowrap">
                  {key}
                </td>
                <td class="py-1 text-gray-600 dark:text-gray-300 whitespace-pre-wrap break-all">
                  {value}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) when is_connected?(socket) do
    :net_kernel.monitor_nodes(true)

    send(self(), {:network_tick, 1})

    socket
    |> assign_defaults()
    |> assign(:tick_gen, 1)
  end

  def handle_mount(socket) do
    socket
    |> assign_defaults()
    |> assign(:tick_gen, 0)
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:services, services())
    |> assign(:rows, nil)
    |> assign(:sockets, nil)
    |> assign(:previous_counters, %{})
    |> assign(:details, nil)
    |> assign(:sample_error, nil)
    |> assign(:form, to_form(default_form_options()))
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Network")
  end

  @impl Page
  def handle_parent_event("form-update", params, socket) do
    service_changed? = params["service"] != socket.assigns.form.params["service"]

    socket =
      if service_changed? do
        socket
        |> assign(:previous_counters, %{})
        |> assign(:details, nil)
        |> assign(:rows, nil)
        |> assign(:sockets, nil)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:form, to_form(params))
     |> restart_tick_chain()}
  end

  def handle_parent_event("network-refresh", _params, socket) do
    {:noreply, restart_tick_chain(socket)}
  end

  def handle_parent_event("network-select-row", %{"index" => index}, socket) do
    case Enum.at(socket.assigns.rows || [], positive_int(index, 0)) do
      nil -> {:noreply, socket}
      row -> {:noreply, assign(socket, :details, row)}
    end
  end

  def handle_parent_event("network-details-close", _params, socket) do
    {:noreply, assign(socket, :details, nil)}
  end

  defp restart_tick_chain(socket) do
    tick_gen = socket.assigns.tick_gen + 1
    send(self(), {:network_tick, tick_gen})

    assign(socket, :tick_gen, tick_gen)
  end

  @impl Page
  def handle_info({:network_tick, gen}, %{assigns: %{tick_gen: gen}} = socket) do
    socket =
      case Network.sample(selected_service(socket)) do
        {:ok, sample} -> assign_sample(socket, sample)
        {:error, reason} -> assign(socket, :sample_error, reason)
      end

    refresh_seconds = positive_int(socket.assigns.form.params["refresh_seconds"], 0)

    if refresh_seconds > 0 do
      Process.send_after(self(), {:network_tick, gen}, refresh_seconds * 1_000)
    end

    {:noreply, socket}
  end

  def handle_info({:network_tick, _stale_gen}, socket) do
    {:noreply, socket}
  end

  def handle_info({:nodeup, _node}, socket) do
    {:noreply, assign(socket, :services, services())}
  end

  def handle_info({:nodedown, node}, %{assigns: %{form: form}} = socket) do
    socket = assign(socket, :services, services())

    if to_string(node) == form.params["service"] do
      params = %{form.params | "service" => to_string(Node.self())}

      {:noreply,
       socket
       |> assign(:form, to_form(params))
       |> assign(:previous_counters, %{})
       |> assign(:details, nil)
       |> restart_tick_chain()}
    else
      {:noreply, socket}
    end
  end

  defp assign_sample(socket, %{ports: ports, sockets: sockets}) do
    %{form: form, previous_counters: previous_counters, details: details} = socket.assigns

    sort_by = sort_by_atom(form.params["sort_by"])

    rows = Network.rank_ports(ports, sort_by, 250, previous_counters)

    details =
      if details do
        Enum.find(rows, &(&1.port == details.port))
      end

    socket
    |> assign(:rows, rows)
    |> assign(:sockets, Enum.sort_by(sockets, &(&1.read_bytes + &1.write_bytes), :desc))
    |> assign(:previous_counters, Network.counters_by_port(ports))
    |> assign(:details, details)
    |> assign(:sample_error, nil)
  end

  defp details_rows(details) do
    [
      {"owner", details.owner_label},
      {"driver", details.name},
      {"recv (total)", format_bytes(details.recv_oct)},
      {"sent (total)", format_bytes(details.send_oct)},
      {"queue size", to_string(details.queue_size)},
      {"memory", format_bytes(details.memory)},
      {"statistics", inspect(Keyword.get(details.inet, :statistics, []), limit: 30)},
      {"options", inspect(Keyword.get(details.inet, :options, []), limit: 50)}
    ]
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

  defp sort_by_atom("recv"), do: :recv
  defp sort_by_atom("send"), do: :send
  defp sort_by_atom(_total), do: :total

  defp positive_int(value, default) do
    case Integer.parse(value || "") do
      {int, ""} when int >= 0 -> int
      _invalid -> default
    end
  end

  defp default_form_options do
    %{
      "service" => to_string(Node.self()),
      "sort_by" => "total",
      "refresh_seconds" => "5"
    }
  end

  defp attention_msg do
    assigns = %{}

    ~H"""
    The busiest inet ports on the selected service, ranked by bytes received/sent per refresh
    interval, with the local and remote endpoints and the owning process - plus the NIF-based
    socket module sockets that port listings miss. Click DETAILS for a port's full statistics
    and options.
    """
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_024, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"
end
