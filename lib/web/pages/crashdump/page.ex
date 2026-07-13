defmodule Observer.Web.Crashdump.Page do
  @moduledoc """
  This is the live component responsible for the Crashdump pillar: browsing `erl_crash.dump`
  files found in the host-allowlisted `:crashdump_dirs` - pick a dump, watch the parse progress,
  then read the crash slogan and general counters and dig through the dumped processes
  (sortable, searchable, with a full per-process drill-down including the stack dump).

  Parsing reuses OTP's own `:crashdump_viewer` (see `ObserverWeb.Crashdump`); this page is only
  ever a client of that parser on the dashboard node.
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Page
  alias ObserverWeb.Crashdump

  @displayed_rows 250

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="crashdump"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={attention_msg()}
      >
        <:inner_form>
          <.form
            for={@form}
            id="crashdump-update-form"
            class="flex flex-col md:flex-row md:items-end shrink-0 ml-2 mr-2 py-2 text-xs text-center text-zinc-800 dark:text-white whitespace-nowrap gap-x-5 gap-y-1"
            phx-change="form-update"
          >
            <Core.input
              field={@form[:sort_by]}
              type="select"
              label="Sort by"
              options={[
                {"Memory", "memory"},
                {"Reductions", "reds"},
                {"Message Queue", "msg_q_len"}
              ]}
            />

            <Core.input field={@form[:search]} type="text" label="Search" phx-debounce="300" />
          </.form>
        </:inner_form>
        <:inner_button>
          <button
            id="crashdump-refresh"
            phx-click="crashdump-refresh"
            class="phx-submit-loading:opacity-75 lg:rounded-r-xl bg-green-500 dark:bg-green-700 transform active:scale-75 transition-transform hover:bg-green-800 dark:hover:bg-green-800 self-stretch w-40 xl:w-64 flex items-center justify-center text-sm font-semibold text-white active:text-white/80"
          >
            REFRESH
          </button>
        </:inner_button>
      </Attention.content>

      <div class="p-2">
        <div :if={not @available?} class="p-4 text-sm text-gray-500 dark:text-gray-400">
          The <code class="font-mono">:observer</code>
          application is not available on this node, so crash dumps cannot be parsed. Add
          <code class="font-mono">:observer</code>
          to your release's applications to enable it. Enabling it only puts its
          modules on the code path - <code class="font-mono">:observer</code>
          has no application callback and starts no processes (and never any GUI).
        </div>

        <div :if={@available?} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded mb-4">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Upload a crash dump
          </h2>
          <form
            id="crashdump-upload-form"
            phx-change="crashdump-validate"
            phx-submit="crashdump-upload"
            class="p-4"
          >
            <label
              phx-drop-target={@uploads.dump.ref}
              class="flex flex-col items-center justify-center py-6 text-center border border-dashed border-gray-300 dark:border-gray-600 rounded cursor-pointer text-sm text-gray-600 dark:text-gray-300 hover:border-blue-400"
            >
              <span>Drag an <code class="font-mono">erl_crash.dump</code> here, or click to choose</span>
              <.live_file_input upload={@uploads.dump} class="sr-only" />
            </label>

            <div :for={entry <- @uploads.dump.entries} class="mt-3 flex items-center gap-3">
              <span class="text-xs text-gray-700 dark:text-gray-200 truncate">
                {entry.client_name} ({format_bytes(entry.client_size)})
              </span>
              <progress value={entry.progress} max="100" class="flex-1" />
              <button
                type="button"
                phx-click="crashdump-cancel-upload"
                phx-value-ref={entry.ref}
                class="text-xs font-semibold text-gray-500 hover:underline"
              >
                CANCEL
              </button>
              <button
                type="submit"
                class="text-xs font-semibold text-blue-600 dark:text-blue-300 hover:underline"
              >
                LOAD
              </button>
            </div>

            <p :for={err <- upload_errors(@uploads.dump)} class="mt-2 text-xs text-red-500">
              {upload_error_to_string(err)}
            </p>
          </form>
        </div>

        <div
          :if={@available? and match?({:ok, _}, @dumps) and elem(@dumps, 1) != []}
          class="bg-white dark:bg-gray-800 w-full shadow-lg rounded mb-4"
        >
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Crash Dumps on this host
          </h2>
          <Core.table_tracing id="crashdump-files" rows={Enum.with_index(elem(@dumps, 1))}>
            <:col :let={{dump, _index}} label="FILE">{dump.name}</:col>
            <:col :let={{dump, _index}} label="PATH">{dump.path}</:col>
            <:col :let={{dump, _index}} label="SIZE">{format_bytes(dump.size)}</:col>
            <:col :let={{dump, _index}} label="MODIFIED">{format_mtime(dump.mtime)}</:col>
            <:col :let={{_dump, index}} label="">
              <button
                id={"crashdump-load-#{index}"}
                phx-click="crashdump-load"
                phx-value-index={index}
                class="text-xs font-semibold text-blue-600 dark:text-blue-300 hover:underline"
              >
                LOAD
              </button>
            </:col>
          </Core.table_tracing>
        </div>

        <div
          :if={match?({:loading, _, _}, @load_status)}
          class="p-4 bg-white dark:bg-gray-800 w-full shadow-lg rounded mb-4"
        >
          <% {:loading, path, percent} = @load_status %>
          <div class="text-sm text-gray-700 dark:text-gray-200 pb-2">
            Parsing {Path.basename(path)}... {percent}%
          </div>
          <div class="w-full h-2 rounded bg-gray-200 dark:bg-gray-600 overflow-hidden">
            <div class="h-2 rounded bg-blue-500" style={"width: #{percent}%"} />
          </div>
        </div>

        <div :if={@load_error} class="p-4 text-sm text-red-500 dark:text-red-300">
          Could not load the dump: {inspect(@load_error)}
        </div>

        <div :if={@general_info} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded mb-4">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            {Path.basename(loaded_path(@load_status))}
          </h2>
          <div class="px-4 py-2">
            <div class="text-sm font-semibold text-red-600 dark:text-red-300 break-all">
              Slogan: {@general_info[:slogan]}
            </div>
          </div>
          <div class="flex flex-wrap gap-2 px-4 pb-3 text-xs">
            <span
              :for={
                {label, key} <- [
                  {"node", :node_name},
                  {"crashed at", :created},
                  {"OTP", :system_vsn},
                  {"processes", :num_procs},
                  {"ets tables", :num_ets},
                  {"timers", :num_timers},
                  {"atoms", :num_atoms},
                  {"memory", :mem_tot}
                ]
              }
              :if={@general_info[key]}
              class="px-2 py-1 rounded-full bg-gray-50 dark:bg-gray-700 border border-gray-300 text-gray-700 dark:text-gray-200"
            >
              {label}: {@general_info[key]}
            </span>
          </div>
        </div>

        <div :if={@rows != nil} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            Processes at crash time
            <span :if={length(@rows) == @displayed_rows} class="font-normal text-gray-500">
              (showing the top {@displayed_rows})
            </span>
          </h2>
          <Core.table_tracing id="crashdump-procs" rows={Enum.with_index(@rows)}>
            <:col :let={{row, _index}} label="PID">{row.pid}</:col>
            <:col :let={{row, _index}} label="NAME">{row.name}</:col>
            <:col :let={{row, _index}} label="STATE">{row.state}</:col>
            <:col :let={{row, _index}} label="CURRENT FUNCTION">{row.current_func}</:col>
            <:col :let={{row, _index}} label="MSG QUEUE">{row.msg_q_len}</:col>
            <:col :let={{row, _index}} label="REDUCTIONS">{row.reds}</:col>
            <:col :let={{row, _index}} label="MEMORY">{format_bytes(row.memory)}</:col>
            <:col :let={{_row, index}} label="">
              <button
                id={"crashdump-select-row-#{index}"}
                phx-click="crashdump-select-row"
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
              Process {@details[:pid]} {@details[:name]}
            </h2>
            <button
              id="crashdump-details-close"
              phx-click="crashdump-details-close"
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
    Crashdump.subscribe()

    socket
    |> assign_defaults()
    |> allow_dump_upload()
    |> assign(:load_status, Crashdump.status())
    |> refresh_loaded()
  end

  def handle_mount(socket) do
    socket
    |> assign_defaults()
    |> allow_dump_upload()
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:available?, Crashdump.available?())
    |> assign(:dumps, Crashdump.list_dumps())
    |> assign(:load_status, :idle)
    |> assign(:load_error, nil)
    |> assign(:uploaded_temp, nil)
    |> assign(:general_info, nil)
    |> assign(:processes, nil)
    |> assign(:rows, nil)
    |> assign(:details, nil)
    |> assign(:displayed_rows, @displayed_rows)
    |> assign(:form, to_form(%{"sort_by" => "memory", "search" => ""}))
  end

  # The upload lives on the enclosing LiveView (handle_mount pipes its socket) so @uploads.dump
  # is available to this component. Registered even when :observer is unavailable so the assign
  # always exists; the input is only rendered when the parser is available.
  defp allow_dump_upload(socket) do
    # accept: :any - ".dump" has no registered MIME type, and a crash dump can also be named
    # erl_crash.dump with no extension at all. A non-dump file simply fails to parse and the
    # error is shown.
    allow_upload(socket, :dump,
      accept: :any,
      max_entries: 1,
      max_file_size: 2_000_000_000
    )
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Crashdump")
  end

  @impl Page
  def handle_parent_event("form-update", params, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params))
     |> assign_rows()}
  end

  def handle_parent_event("crashdump-refresh", _params, socket) do
    {:noreply, assign(socket, :dumps, Crashdump.list_dumps())}
  end

  # LiveView needs a phx-change handler for the upload form to track the selected entry.
  def handle_parent_event("crashdump-validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_parent_event("crashdump-cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :dump, ref)}
  end

  def handle_parent_event("crashdump-upload", _params, socket) do
    # consume_uploaded_entries deletes the temp file once the callback returns, but the parser
    # re-reads the file for every query (general_info/processes/proc_details) - so copy it to a
    # stable temp path that survives the session, cleaning up the previous upload.
    consumed =
      consume_uploaded_entries(socket, :dump, fn %{path: tmp_path}, entry ->
        dest =
          Path.join(
            System.tmp_dir!(),
            "observer_web_crashdump_upload_#{System.unique_integer([:positive])}_#{entry.client_name}"
          )

        File.cp!(tmp_path, dest)
        {:ok, dest}
      end)

    case consumed do
      [dest] ->
        if socket.assigns.uploaded_temp, do: File.rm(socket.assigns.uploaded_temp)

        case Crashdump.load_upload(dest) do
          :ok -> {:noreply, start_loading(socket, dest) |> assign(:uploaded_temp, dest)}
          {:error, reason} -> {:noreply, assign(socket, :load_error, reason)}
        end

      [] ->
        {:noreply, socket}
    end
  end

  def handle_parent_event("crashdump-load", %{"index" => index}, socket) do
    with {:ok, dumps} <- socket.assigns.dumps,
         %{path: path} <- Enum.at(dumps, positive_int(index, 0)) do
      case Crashdump.load(path) do
        :ok -> {:noreply, start_loading(socket, path)}
        {:error, reason} -> {:noreply, assign(socket, :load_error, reason)}
      end
    else
      _unknown -> {:noreply, socket}
    end
  end

  def handle_parent_event("crashdump-select-row", %{"index" => index}, socket) do
    case Enum.at(socket.assigns.rows || [], positive_int(index, 0)) do
      nil ->
        {:noreply, socket}

      row ->
        case Crashdump.proc_details(row.pid) do
          {:ok, details} -> {:noreply, assign(socket, :details, details)}
          {:error, _reason} -> {:noreply, socket}
        end
    end
  end

  def handle_parent_event("crashdump-details-close", _params, socket) do
    {:noreply, assign(socket, :details, nil)}
  end

  @impl Page
  def handle_info({:crashdump_progress, {:loading, path, percent}}, socket) do
    {:noreply, assign(socket, :load_status, {:loading, path, percent})}
  end

  def handle_info({:crashdump_progress, {:loaded, path}}, socket) do
    {:noreply,
     socket
     |> assign(:load_status, {:loaded, path})
     |> refresh_loaded()}
  end

  def handle_info({:crashdump_progress, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:load_status, :idle)
     |> assign(:load_error, reason)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh_loaded(%{assigns: %{load_status: {:loaded, _path}}} = socket) do
    with {:ok, info} <- Crashdump.general_info(),
         {:ok, processes} <- Crashdump.processes() do
      socket
      |> assign(:general_info, info)
      |> assign(:processes, processes)
      |> assign_rows()
    else
      # coveralls-ignore-start
      {:error, _reason} ->
        socket
        # coveralls-ignore-stop
    end
  end

  defp refresh_loaded(socket), do: socket

  defp start_loading(socket, path) do
    socket
    |> assign(:load_status, {:loading, path, 0})
    |> assign(:load_error, nil)
    |> assign(:general_info, nil)
    |> assign(:processes, nil)
    |> assign(:rows, nil)
    |> assign(:details, nil)
  end

  defp assign_rows(%{assigns: %{processes: nil}} = socket), do: socket

  defp assign_rows(%{assigns: %{processes: processes, form: form}} = socket) do
    search = String.downcase(form.params["search"] || "")

    sort_by =
      case form.params["sort_by"] do
        "reds" -> :reds
        "msg_q_len" -> :msg_q_len
        _memory -> :memory
      end

    rows =
      processes
      |> Enum.filter(fn row ->
        search == "" or
          String.contains?(String.downcase("#{row.name} #{row.pid}"), search)
      end)
      |> Enum.sort_by(&(&1[sort_by] || 0), :desc)
      |> Enum.take(@displayed_rows)

    assign(socket, :rows, rows)
  end

  defp details_rows(details) do
    main = ~w(state init_func parent start_time current_func msg_q_len reds memory stack_heap
              links monitors mon_by run_queue int_state dict msg_q last_calls stack_dump)a

    main
    |> Enum.flat_map(fn key ->
      case details[key] do
        nil -> []
        value -> [{key |> to_string() |> String.replace("_", " "), to_string(value)}]
      end
    end)
  end

  defp loaded_path({:loaded, path}), do: path
  defp loaded_path(_other), do: ""

  defp positive_int(value, default) do
    case Integer.parse(value || "") do
      {int, ""} when int >= 0 -> int
      _invalid -> default
    end
  end

  defp attention_msg do
    assigns = %{}

    ~H"""
    Inspect Erlang crash dumps: upload one from your machine (e.g. pulled off a crashed device)
    or browse dumps present on the dashboard host, then read the crash slogan, the VM's state at
    crash time and every dumped process including stacks and message queues. Parsing happens on
    the dashboard node with OTP's own crashdump_viewer parser - nothing is fetched from remote
    nodes.
    """
  end

  defp upload_error_to_string(:too_large), do: "The file is larger than the allowed size."
  defp upload_error_to_string(:too_many_files), do: "Only one dump can be loaded at a time."
  # coveralls-ignore-start
  defp upload_error_to_string(other), do: "Upload failed: #{inspect(other)}"
  # coveralls-ignore-stop

  defp format_mtime(posix) do
    posix |> DateTime.from_unix!() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_024,
    do: "#{Float.round(bytes / 1_024, 1)} KB"

  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_bytes(other), do: to_string(other)
end
