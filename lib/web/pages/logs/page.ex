defmodule Observer.Web.Logs.Page do
  @moduledoc """
  This is the live component responsible for the Logs pillar: a bounded tail of the selected
  node's file-backed logger handlers - read the end of a production log during an incident
  without shelling into the box (see `ObserverWeb.Logs`).
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Page
  alias ObserverWeb.Logs

  @tail_sizes [{"16 KB", 16_384}, {"64 KB", 65_536}, {"256 KB", 262_144}, {"1 MB", 1_048_576}]

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="logs"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={attention_msg()}
      >
        <:inner_form>
          <.form
            for={@form}
            id="logs-update-form"
            class="flex flex-col md:flex-row md:items-end shrink-0 ml-2 mr-2 py-2 text-xs text-center text-zinc-800 dark:text-white whitespace-nowrap gap-x-5 gap-y-1"
            phx-change="form-update"
          >
            <Core.input field={@form[:service]} type="select" label="Service" options={@services} />
            <Core.input
              field={@form[:file]}
              type="select"
              label="Log File"
              options={Enum.map(@handlers, & &1.file)}
            />
            <Core.input
              field={@form[:max_bytes]}
              type="select"
              label="Tail Size"
              options={Enum.map(tail_sizes(), fn {label, bytes} -> {label, to_string(bytes)} end)}
            />
          </.form>
        </:inner_form>
        <:inner_button>
          <button
            id="logs-refresh"
            phx-click="logs-refresh"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 dark:bg-green-700 transform active:scale-75 transition-transform hover:bg-green-800 dark:hover:bg-green-800 self-stretch w-40 xl:w-64 flex items-center justify-center text-sm font-semibold text-white active:text-white/80"
          >
            REFRESH
          </button>
        </:inner_button>
      </Attention.content>

      <div class="p-2">
        <div :if={@tail_error} class="p-4 text-sm text-red-500 dark:text-red-300">
          Could not read {@form.params["file"]}: {inspect(@tail_error)}
        </div>

        <div :if={@handlers == []} class="p-4 text-sm text-gray-500 dark:text-gray-400">
          No file-backed logger handlers found on {@form.params["service"]}. Logs are read from
          the node's <span class="font-mono font-semibold">:logger</span>
          handlers configured with a <span class="font-mono font-semibold">:file</span>
          option (e.g. <span class="font-mono font-semibold">:logger_std_h</span>
          pointing at a log file path).
        </div>

        <div :if={@tail} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded">
          <div class="flex flex-wrap gap-2 px-4 py-2 text-xs">
            <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
              File size: {format_bytes(@tail.size)}
            </span>
            <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
              Entries: {length(@log_entries)}
            </span>
            <span
              :if={@tail.truncated?}
              class="px-2 py-1 rounded-full bg-yellow-50 border border-yellow-300 text-yellow-700"
            >
              Showing the last {@form.params["max_bytes"] |> String.to_integer() |> format_bytes()}
            </span>
          </div>
          <div
            :if={@log_entries == []}
            class="mx-2 mb-2 p-3 text-xs text-gray-500 dark:text-gray-400"
          >
            The file is empty.
          </div>
          <div
            :if={@log_entries != []}
            id="logs-tail-content"
            class="mx-2 mb-2 p-3 rounded bg-gray-50 dark:bg-gray-900 text-xs text-gray-800 dark:text-gray-200 font-mono max-h-[70vh] overflow-y-auto"
          >
            <Core.disclosure
              :for={{entry, index} <- Enum.with_index(@log_entries)}
              id={"log-entry-#{index}"}
              expandable?={entry.expandable?}
              summary_class={level_class(entry.level)}
              title={entry.summary}
            >
              <:summary>
                {entry.summary}
                <span :if={entry.multiline?} class="text-gray-400 dark:text-gray-500">…</span>
              </:summary>
              <pre class="mt-1 mb-2 whitespace-pre-wrap break-all text-gray-700 dark:text-gray-300">{entry.content}</pre>
            </Core.disclosure>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) when is_connected?(socket) do
    :net_kernel.monitor_nodes(true)

    send(self(), :logs_refresh)

    assign_defaults(socket)
  end

  def handle_mount(socket) do
    assign_defaults(socket)
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:services, services())
    |> assign(:handlers, [])
    |> assign(:tail, nil)
    |> assign(:log_entries, [])
    |> assign(:tail_error, nil)
    |> assign(
      :form,
      to_form(%{
        "service" => to_string(Node.self()),
        "file" => "",
        "max_bytes" => "65536"
      })
    )
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Logs")
  end

  @impl Page
  def handle_parent_event("form-update", params, socket) do
    send(self(), :logs_refresh)

    {:noreply, assign(socket, :form, to_form(params))}
  end

  def handle_parent_event("logs-refresh", _params, socket) do
    send(self(), :logs_refresh)

    {:noreply, socket}
  end

  @impl Page
  def handle_info(:logs_refresh, %{assigns: %{form: form}} = socket) do
    node = selected_service(socket)
    handlers = Logs.list_handlers(node)

    file = selected_file(form.params["file"], handlers)
    max_bytes = selected_max_bytes(form.params["max_bytes"])

    # Map.put instead of the %{map | key} update syntax: a node without file handlers renders
    # an empty file select, so the phx-change payload arrives without a "file" key at all.
    form =
      form.params
      |> Map.put("file", file || "")
      |> Map.put("max_bytes", to_string(max_bytes))
      |> to_form()

    socket =
      socket
      |> assign(:handlers, handlers)
      |> assign(:form, form)

    case file && Logs.tail(node, file, max_bytes) do
      {:ok, tail} ->
        tail = %{tail | content: strip_ansi(tail.content)}

        {:noreply,
         socket
         |> assign(:tail, tail)
         |> assign(:log_entries, parse_entries(tail.content))
         |> assign(:tail_error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:tail, nil)
         |> assign(:log_entries, [])
         |> assign(:tail_error, reason)}

      nil ->
        {:noreply,
         socket
         |> assign(:tail, nil)
         |> assign(:log_entries, [])
         |> assign(:tail_error, nil)}
    end
  end

  def handle_info({:nodeup, _node}, socket) do
    {:noreply, assign(socket, :services, services())}
  end

  def handle_info({:nodedown, node}, %{assigns: %{form: form}} = socket) do
    socket = assign(socket, :services, services())

    if to_string(node) == form.params["service"] do
      send(self(), :logs_refresh)

      {:noreply,
       assign(socket, :form, to_form(Map.put(form.params, "service", to_string(Node.self()))))}
    else
      {:noreply, socket}
    end
  end

  # Log files written by color-enabled formatters (Logger's default when attached in a
  # terminal) are full of ANSI escape sequences that render as garbage in the pane.
  defp strip_ansi(content), do: String.replace(content, ~r/\e\[[0-9;]*[a-zA-Z]/, "")

  # A new entry starts at a line that looks like a log head: a time (Elixir's default
  # formatter), a date, or an Erlang report banner. Anything else (stack traces, wrapped
  # output, blank separators) is a continuation of the previous entry, so multi-line entries
  # collapse behind their first line - same disclosure pattern as the tracing results.
  @entry_start ~r/^(\d{4}-\d{2}-\d{2}[T ]|\d{2}:\d{2}:\d{2}|=[A-Z ]+ REPORT====)/

  defp parse_entries(content) do
    content
    |> String.split("\n")
    |> Enum.chunk_while(
      [],
      fn line, acc ->
        cond do
          acc == [] -> {:cont, [line]}
          String.match?(line, @entry_start) -> {:cont, Enum.reverse(acc), [line]}
          true -> {:cont, [line | acc]}
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.map(&build_entry/1)
    |> Enum.reject(&(&1.summary == ""))
  end

  # Beyond this length a single-line entry is almost certainly clipped by the summary's
  # truncate, so it stays expandable even without continuation lines.
  @long_line_threshold 160

  defp build_entry(lines) do
    meaningful_lines = Enum.reject(lines, &(String.trim(&1) == ""))
    summary = List.first(meaningful_lines) || ""
    multiline? = length(meaningful_lines) > 1

    %{
      summary: summary,
      content: Enum.join(meaningful_lines, "\n"),
      multiline?: multiline?,
      expandable?: multiline? or String.length(summary) > @long_line_threshold,
      level: detect_level(summary)
    }
  end

  defp detect_level(summary) do
    cond do
      summary =~ ~r/\[(error|critical|alert|emergency)\]|=(ERROR|CRASH) REPORT/ -> :error
      summary =~ ~r/\[warn(ing)?\]|=WARNING REPORT/ -> :warning
      true -> nil
    end
  end

  defp level_class(:error), do: "text-red-600 dark:text-red-300"
  defp level_class(:warning), do: "text-yellow-600 dark:text-yellow-300"
  defp level_class(nil), do: nil

  defp tail_sizes, do: @tail_sizes

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

  # Only files exposed by the node's logger handlers are ever requested - anything else in the
  # form payload falls back to the first known handler.
  defp selected_file(file, handlers) do
    files = Enum.map(handlers, & &1.file)

    if file in files, do: file, else: List.first(files)
  end

  defp selected_max_bytes(value) do
    allowed = Enum.map(tail_sizes(), fn {_label, bytes} -> bytes end)

    case Integer.parse(value || "") do
      {bytes, ""} -> Enum.find(allowed, 65_536, &(&1 == bytes))
      _invalid -> 65_536
    end
  end

  defp attention_msg do
    assigns = %{}

    ~H"""
    A bounded, read-only tail of the selected service's file-backed logger handlers. Only files
    configured on the node's :logger handlers can be read, and never more than the selected tail
    size. Data is collected on demand - press REFRESH to update.
    """
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_024, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"
end
