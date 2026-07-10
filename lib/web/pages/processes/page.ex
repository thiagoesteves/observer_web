defmodule Observer.Web.Processes.Page do
  @moduledoc """
  This is the live component responsible for the Processes pillar: an etop-style, auto-refreshing
  table of the busiest processes on a selected node, ranked by reductions (delta per refresh
  interval), memory or message queue length, with a per-process drill-down panel.

  Refresh ticks carry a generation counter: changing any control bumps the generation and starts
  a new timer chain, so a tick from a cancelled chain that was already in flight is ignored
  instead of spawning a second chain.
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Page
  alias ObserverWeb.Processes

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="processes"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={attention_msg()}
      >
        <:inner_form>
          <.form
            for={@form}
            id="processes-update-form"
            class="flex flex-col md:flex-row md:items-end shrink-0 ml-2 mr-2 py-2 text-xs text-center text-zinc-800 dark:text-white whitespace-nowrap gap-x-5 gap-y-1"
            phx-change="form-update"
          >
            <Core.input
              field={@form[:service]}
              type="select"
              label="Service"
              options={@services}
            />

            <Core.input
              field={@form[:sort_by]}
              type="select"
              label="Sort by"
              options={[
                {"Reductions", "reductions"},
                {"Memory", "memory"},
                {"Message Queue", "message_queue_len"}
              ]}
            />

            <Core.input
              field={@form[:limit]}
              type="select"
              label="Top"
              options={[{"25", "25"}, {"50", "50"}, {"100", "100"}, {"250", "250"}]}
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
            id="processes-refresh"
            phx-click="processes-refresh"
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
          :if={@summary == nil and @sample_error == nil}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Collecting processes...
        </div>

        <div :if={@summary} class="flex flex-wrap gap-2 px-2 pb-2 text-xs">
          <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
            Processes: {@summary.process_count}
          </span>
          <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
            Run Queue: {@summary.run_queue}
          </span>
          <span
            :for={key <- [:total, :processes, :ets, :binary, :atom, :code]}
            class="px-2 py-1 rounded-full bg-blue-50 border border-blue-300 text-blue-700"
          >
            {key}: {format_bytes(Map.get(@summary.memory, key, 0))}
          </span>
        </div>

        <div :if={@rows != []} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded">
          <Core.table_tracing id="processes-results" rows={Enum.with_index(@rows)}>
            <:col :let={{row, _index}} label="NAME">{row.name}</:col>
            <:col :let={{row, _index}} label="PID">{inspect(row.pid)}</:col>
            <:col :let={{row, _index}} label="MEMORY">{format_bytes(row.memory)}</:col>
            <:col :let={{row, _index}} label={reductions_label(@form.params["sort_by"])}>
              {row.reductions_diff}
            </:col>
            <:col :let={{row, _index}} label="MSG QUEUE">{row.message_queue_len}</:col>
            <:col :let={{row, _index}} label="CURRENT FUNCTION">{row.current_function}</:col>
            <:col :let={{_row, index}} label="">
              <button
                id={"processes-select-row-#{index}"}
                phx-click="processes-select-row"
                phx-value-index={index}
                class="text-xs font-semibold text-blue-600 dark:text-blue-300 hover:underline"
              >
                DETAILS
              </button>
            </:col>
          </Core.table_tracing>
        </div>

        <div
          :if={@details}
          class="mt-4 bg-white dark:bg-gray-800 w-full shadow-lg rounded border border-gray-200 dark:border-gray-600"
        >
          <div class="flex items-center justify-between px-4 pt-2">
            <h2 class="text-sm font-semibold text-gray-700 dark:text-gray-200">
              Process {inspect(@details.pid)}
            </h2>
            <button
              id="processes-details-close"
              phx-click="processes-details-close"
              class="text-xs font-semibold text-gray-500 dark:text-gray-300 hover:underline"
            >
              CLOSE
            </button>
          </div>
          <div :if={@details.info == :not_found} class="p-4 text-sm text-gray-500">
            The process has exited.
          </div>
          <table :if={is_list(@details.info)} class="w-full text-left text-xs m-2">
            <tbody>
              <tr :for={{key, value} <- @details.info} class="align-top">
                <td class="py-1 pr-4 font-semibold text-gray-700 dark:text-gray-200 whitespace-nowrap capitalize">
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

    send(self(), {:processes_tick, 1})

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
    |> assign(:rows, [])
    |> assign(:summary, nil)
    |> assign(:previous_reductions, %{})
    |> assign(:details, nil)
    |> assign(:sample_error, nil)
    |> assign(:form, to_form(default_form_options()))
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Processes")
  end

  @impl Page
  def handle_parent_event("form-update", params, socket) do
    service_changed? = params["service"] != socket.assigns.form.params["service"]

    socket =
      if service_changed? do
        socket
        |> assign(:previous_reductions, %{})
        |> assign(:details, nil)
        |> assign(:summary, nil)
        |> assign(:rows, [])
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:form, to_form(params))
     |> restart_tick_chain()}
  end

  def handle_parent_event("processes-refresh", _params, socket) do
    {:noreply, restart_tick_chain(socket)}
  end

  def handle_parent_event("processes-select-row", %{"index" => index}, socket) do
    case Enum.at(socket.assigns.rows, positive_int(index, 0)) do
      nil -> {:noreply, socket}
      row -> {:noreply, assign(socket, :details, fetch_details(row.pid))}
    end
  end

  def handle_parent_event("processes-details-close", _params, socket) do
    {:noreply, assign(socket, :details, nil)}
  end

  # Bumps the generation and fires an immediate tick - any tick still in flight from the
  # previous chain is dropped by the generation guard in handle_info/2.
  defp restart_tick_chain(socket) do
    tick_gen = socket.assigns.tick_gen + 1
    send(self(), {:processes_tick, tick_gen})

    assign(socket, :tick_gen, tick_gen)
  end

  @impl Page
  def handle_info({:processes_tick, gen}, %{assigns: %{tick_gen: gen}} = socket) do
    socket =
      case Processes.sample(selected_service(socket)) do
        {:ok, sample} -> assign_sample(socket, sample)
        {:error, reason} -> assign(socket, :sample_error, reason)
      end

    refresh_seconds = positive_int(socket.assigns.form.params["refresh_seconds"], 0)

    if refresh_seconds > 0 do
      Process.send_after(self(), {:processes_tick, gen}, refresh_seconds * 1_000)
    end

    {:noreply, socket}
  end

  def handle_info({:processes_tick, _stale_gen}, socket) do
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
       |> assign(:previous_reductions, %{})
       |> assign(:details, nil)
       |> restart_tick_chain()}
    else
      {:noreply, socket}
    end
  end

  defp assign_sample(socket, sample) do
    %{form: form, previous_reductions: previous_reductions, details: details} = socket.assigns

    sort_by = sort_by_atom(form.params["sort_by"])
    limit = positive_int(form.params["limit"], 50)

    rows = Processes.rank(sample, sort_by, limit, previous_reductions)

    details =
      if details do
        fetch_details(details.pid)
      end

    socket
    |> assign(:rows, rows)
    |> assign(
      :summary,
      Map.take(sample, [:process_count, :run_queue, :memory])
    )
    |> assign(:previous_reductions, Processes.reductions_by_pid(sample))
    |> assign(:details, details)
    |> assign(:sample_error, nil)
  end

  defp fetch_details(pid) do
    case Processes.details(pid) do
      {:ok, info} -> %{pid: pid, info: info}
      {:error, :not_found} -> %{pid: pid, info: :not_found}
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

  defp sort_by_atom("memory"), do: :memory
  defp sort_by_atom("message_queue_len"), do: :message_queue_len
  defp sort_by_atom(_reductions), do: :reductions

  defp positive_int(value, default) do
    case Integer.parse(value || "") do
      {int, ""} when int >= 0 -> int
      _invalid -> default
    end
  end

  defp default_form_options do
    %{
      "service" => to_string(Node.self()),
      "sort_by" => "reductions",
      "limit" => "50",
      "refresh_seconds" => "5"
    }
  end

  defp reductions_label("reductions"), do: "REDUCTIONS (Δ)"
  defp reductions_label(_other), do: "REDUCTIONS"

  defp attention_msg do
    assigns = %{}

    ~H"""
    Lists the busiest processes on the selected service, ranked by reductions (delta per refresh
    interval), memory or message queue length - the same bounded collector etop uses. While this
    page is open the <b>:scheduler_wall_time</b>
    flag is enabled on the sampled node (etop behaves the same way); it is switched back off when
    the page is closed.
    """
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_024, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"
end
