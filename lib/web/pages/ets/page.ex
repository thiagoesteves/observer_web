defmodule Observer.Web.Ets.Page do
  @moduledoc """
  This is the live component responsible for the ETS pillar: every ETS table on a selected node
  with its metadata (owner, protection, type, size, memory), searchable and sortable, plus an
  optional bounded content preview gated behind the `:ets_content_inspection` config (see
  `ObserverWeb.Ets` - table contents are live production data, so previews are off by default).
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Page
  alias ObserverWeb.Ets

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="ets"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={attention_msg()}
      >
        <:inner_form>
          <.form
            for={@form}
            id="ets-update-form"
            class="flex shrink-0 ml-2 mr-2 text-xs text-center text-zinc-800 dark:text-white whitespace-nowrap gap-5"
            phx-change="form-update"
          >
            <Core.input field={@form[:service]} type="select" label="Service" options={@services} />

            <Core.input
              field={@form[:sort_by]}
              type="select"
              label="Sort by"
              options={[{"Memory", "memory"}, {"Size", "size"}, {"Name", "name"}]}
            />

            <Core.input field={@form[:search]} type="text" label="Search" phx-debounce="300" />
          </.form>
        </:inner_form>
        <:inner_button>
          <button
            id="ets-refresh"
            phx-click="ets-refresh"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 dark:bg-green-700 transform active:scale-75 transition-transform hover:bg-green-800 dark:hover:bg-green-800 py-10 w-64 text-sm font-semibold text-white active:text-white/80"
          >
            REFRESH
          </button>
        </:inner_button>
      </Attention.content>

      <div class="p-2">
        <div :if={@tables_error} class="p-4 text-sm text-red-500 dark:text-red-300">
          Could not list tables on {@form.params["service"]}: {inspect(@tables_error)}
        </div>

        <div
          :if={@tables == nil and @tables_error == nil}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Collecting ETS tables...
        </div>

        <div :if={@tables} class="flex flex-wrap gap-2 px-2 pb-2 text-xs">
          <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
            Tables: {length(@tables)}
          </span>
          <span class="px-2 py-1 rounded-full bg-blue-50 border border-blue-300 text-blue-700">
            Total memory: {format_bytes(Enum.sum(Enum.map(@tables, & &1.memory)))}
          </span>
          <span
            :if={@rows != nil and length(@rows) != length(@tables)}
            class="px-2 py-1 rounded-full bg-gray-50 border border-gray-300 text-gray-700"
          >
            Showing: {length(@rows)}
          </span>
        </div>

        <div
          :if={@rows != nil and @rows != []}
          class="bg-white dark:bg-gray-800 w-full shadow-lg rounded"
        >
          <Core.table_tracing id="ets-results" rows={Enum.with_index(@rows)}>
            <:col :let={{table, _index}} label="NAME">{inspect(table.name)}</:col>
            <:col :let={{table, _index}} label="TYPE">{table.type}</:col>
            <:col :let={{table, _index}} label="PROTECTION">{table.protection}</:col>
            <:col :let={{table, _index}} label="OWNER">{table.owner_label}</:col>
            <:col :let={{table, _index}} label="OBJECTS">{table.size}</:col>
            <:col :let={{table, _index}} label="MEMORY">{format_bytes(table.memory)}</:col>
            <:col :let={{_table, index}} label="">
              <button
                id={"ets-select-row-#{index}"}
                phx-click="ets-select-row"
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
              Table {inspect(@details.table.name)}
            </h2>
            <button
              id="ets-details-close"
              phx-click="ets-details-close"
              class="text-xs font-semibold text-gray-500 dark:text-gray-300 hover:underline"
            >
              CLOSE
            </button>
          </div>

          <div class="flex flex-wrap gap-2 px-4 py-2 text-xs">
            <span
              :for={
                {label, value} <- [
                  {"type", @details.table.type},
                  {"protection", @details.table.protection},
                  {"owner", @details.table.owner_label},
                  {"objects", @details.table.size},
                  {"memory", format_bytes(@details.table.memory)},
                  {"compressed", @details.table.compressed}
                ]
              }
              class="px-2 py-1 rounded-full bg-gray-50 dark:bg-gray-700 border border-gray-300 text-gray-700 dark:text-gray-200"
            >
              {label}: {value}
            </span>
          </div>

          <div
            :if={@details.content == {:error, :content_inspection_disabled}}
            class="px-4 pb-4 text-xs text-gray-500 dark:text-gray-400"
          >
            Content inspection is disabled. Table contents are live production data - to enable
            bounded, read-only previews, set <code class="font-mono">config :observer_web, ets_content_inspection: true</code>.
          </div>

          <div
            :if={@details.content == {:error, :not_accessible}}
            class="px-4 pb-4 text-xs text-gray-500 dark:text-gray-400"
          >
            This table's contents are not accessible (private table, or it no longer exists).
          </div>

          <div :if={match?({:ok, _}, @details.content)} class="px-4 pb-4">
            <h3 class="text-xs font-semibold text-gray-700 dark:text-gray-200 pb-1">
              First objects (bounded preview)
            </h3>
            <div :if={elem(@details.content, 1) == []} class="text-xs text-gray-500">
              The table is empty.
            </div>
            <ul class="text-xs font-mono text-gray-600 dark:text-gray-300 space-y-1 break-all">
              <li :for={object <- elem(@details.content, 1)}>{object}</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) when is_connected?(socket) do
    :net_kernel.monitor_nodes(true)

    send(self(), :ets_refresh)

    assign_defaults(socket)
  end

  def handle_mount(socket) do
    assign_defaults(socket)
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:services, services())
    |> assign(:tables, nil)
    |> assign(:rows, nil)
    |> assign(:details, nil)
    |> assign(:tables_error, nil)
    |> assign(
      :form,
      to_form(%{"service" => to_string(Node.self()), "sort_by" => "memory", "search" => ""})
    )
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "ETS")
  end

  @impl Page
  def handle_parent_event("form-update", params, socket) do
    service_changed? = params["service"] != socket.assigns.form.params["service"]

    socket = assign(socket, :form, to_form(params))

    if service_changed? do
      send(self(), :ets_refresh)

      {:noreply,
       socket
       |> assign(:tables, nil)
       |> assign(:rows, nil)
       |> assign(:details, nil)}
    else
      {:noreply, assign_rows(socket)}
    end
  end

  def handle_parent_event("ets-refresh", _params, socket) do
    send(self(), :ets_refresh)

    {:noreply, socket}
  end

  def handle_parent_event("ets-select-row", %{"index" => index}, socket) do
    case Enum.at(socket.assigns.rows || [], positive_int(index, 0)) do
      nil ->
        {:noreply, socket}

      table ->
        node = selected_service(socket)
        content = Ets.table_content(node, table.handle)

        {:noreply, assign(socket, :details, %{table: table, content: content})}
    end
  end

  def handle_parent_event("ets-details-close", _params, socket) do
    {:noreply, assign(socket, :details, nil)}
  end

  @impl Page
  def handle_info(:ets_refresh, socket) do
    case Ets.list_tables(selected_service(socket)) do
      {:ok, tables} ->
        {:noreply,
         socket
         |> assign(:tables, tables)
         |> assign(:tables_error, nil)
         |> assign_rows()}

      {:error, reason} ->
        {:noreply, assign(socket, :tables_error, reason)}
    end
  end

  def handle_info({:nodeup, _node}, socket) do
    {:noreply, assign(socket, :services, services())}
  end

  def handle_info({:nodedown, node}, %{assigns: %{form: form}} = socket) do
    socket = assign(socket, :services, services())

    if to_string(node) == form.params["service"] do
      send(self(), :ets_refresh)

      params = %{form.params | "service" => to_string(Node.self())}

      {:noreply,
       socket
       |> assign(:form, to_form(params))
       |> assign(:details, nil)}
    else
      {:noreply, socket}
    end
  end

  defp assign_rows(%{assigns: %{tables: nil}} = socket), do: socket

  defp assign_rows(%{assigns: %{tables: tables, form: form}} = socket) do
    search = String.downcase(form.params["search"] || "")

    sort_by =
      case form.params["sort_by"] do
        "size" -> :size
        "name" -> :name
        _memory -> :memory
      end

    rows =
      tables
      |> Enum.filter(
        &(search == "" or String.contains?(String.downcase(inspect(&1.name)), search))
      )
      |> sort_rows(sort_by)

    assign(socket, :rows, rows)
  end

  defp sort_rows(tables, :name), do: Enum.sort_by(tables, &inspect(&1.name))
  defp sort_rows(tables, key), do: Enum.sort_by(tables, &Map.fetch!(&1, key), :desc)

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

  defp positive_int(value, default) do
    case Integer.parse(value || "") do
      {int, ""} when int >= 0 -> int
      _invalid -> default
    end
  end

  defp attention_msg do
    assigns = %{}

    ~H"""
    Every ETS table on the selected service with its owner, protection, type and memory
    footprint. Table contents are live production data: previews are read-only, bounded to the
    first objects, and disabled unless explicitly enabled in the configuration. Data is collected
    on demand - press REFRESH to update.
    """
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_024, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"
end
