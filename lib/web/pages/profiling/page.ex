defmodule Observer.Web.Profiling.Page do
  @moduledoc """
  This is the live component responsible for handling the Profiling tools (Count, Duration, Call
  Sequence, Flame Graph - only Count is wired up so far). Shares the node/module/function
  selection logic with `Observer.Web.Tracing.Page` via `Observer.Web.Tracing.Selection`, but runs
  its sessions with a `tool` selected instead of the raw match-spec picker, and shows a single
  aggregated report instead of a live event stream.
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Components.MultiSelectList
  alias Observer.Web.Page
  alias Observer.Web.Tracing.Selection
  alias ObserverWeb.Tracer

  @impl Phoenix.LiveComponent
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_modules_keys =
      assigns.node_info.modules_keys -- assigns.node_info.selected_modules_keys

    unselected_functions_keys =
      assigns.node_info.functions_keys -- assigns.node_info.selected_functions_keys

    trace_state = Tracer.state()

    trace_idle? = trace_state.status == :idle
    trace_owner? = trace_state.session_id == assigns.trace_session_id

    show_tracing_options = trace_idle? and trace_owner? and assigns.show_tracing_options

    attention_msg = ~H"""
    Count tallies how many times each traced function was called. Like Live Tracing, it enforces
    limits on the maximum number of events and applies a timeout (in seconds) to ensure the
    debugger doesn't remain active unintentionally.
    """

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_modules_keys: unselected_modules_keys)
      |> assign(unselected_functions_keys: unselected_functions_keys)
      |> assign(trace_idle?: trace_idle?)
      |> assign(trace_owner?: trace_owner?)
      |> assign(show_tracing_options: show_tracing_options)
      |> assign(attention_msg: attention_msg)

    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="profiling"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={@attention_msg}
      >
        <:inner_form>
          <.form
            for={@form}
            id="profiling-update-form"
            class="flex ml-2 mr-2 text-xs text-center text-zinc-800 dark:text-white  whitespace-nowrap gap-5"
            phx-change="form-update"
          >
            <Core.input
              field={@form[:max_messages]}
              type="number"
              step="1"
              min="1"
              max="10000"
              label="Events"
            />

            <Core.input
              field={@form[:session_timeout_seconds]}
              type="number"
              step="15"
              min="30"
              max="300"
              label="Timeout(s)"
            />
          </.form>
        </:inner_form>
        <:inner_button>
          <button
            :if={@trace_idle? and @trace_owner?}
            id="profiling-multi-select-run"
            phx-click="profiling-run"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 dark:bg-green-700 transform active:scale-75 transition-transform hover:bg-green-800 dark:hover:bg-green-800 py-10 w-64 text-sm font-semibold text-white active:text-white/80"
          >
            RUN
          </button>
          <button
            :if={@trace_idle? == false and @trace_owner?}
            id="profiling-multi-select-stop"
            phx-click="profiling-stop"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-red-500 dark:bg-red-700 transform active:scale-75 transition-transform hover:bg-red-600 dark:hover:bg-red-800 py-10 w-64 text-sm font-semibold text-white active:text-white/80 animate-pulse"
          >
            STOP
          </button>

          <button
            :if={not @trace_owner?}
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-red-500 dark:bg-red-700 transform active:scale-75 transition-transform hover:bg-red-600 dark:hover:bg-red-800 py-10 w-64 text-sm font-semibold text-white active:text-white/80 animate-pulse"
          >
            IN USE
          </button>
        </:inner_button>
      </Attention.content>
      <div class="flex">
        <MultiSelectList.content
          id="profiling-multi-select"
          selected_text="Selected Items"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "modules", keys: @node_info.selected_modules_keys},
            %{name: "functions", keys: @node_info.selected_functions_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "modules", keys: @unselected_modules_keys},
            %{name: "functions", keys: @unselected_functions_keys}
          ]}
          show_options={@show_tracing_options}
          form_search={@form_search}
        />
      </div>
      <div class="p-2">
        <div
          :if={@report == nil and not @trace_idle?}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Waiting for the session to end...
        </div>
        <div
          :if={@report == nil and @trace_idle?}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Select functions to trace and press RUN to collect counts.
        </div>
        <Core.table_process
          :if={@report != nil}
          id="profiling-count-results"
          title="Count Results"
          rows={@report}
        >
          <:col :let={{{mod, fun, arity, _message}, _count}} label="FUNCTION">
            {inspect(mod)}.{fun}/{arity}
          </:col>
          <:col :let={{{_mod, _fun, _arity, message}, _count}} label="MESSAGE">
            {inspect(message)}
          </:col>
          <:col :let={{_key, count}} label="COUNT">
            {count}
          </:col>
        </Core.table_process>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) when is_connected?(socket) do
    :net_kernel.monitor_nodes(true)

    socket
    |> assign(:node_info, Selection.update([], [], []))
    |> assign(:trace_session_id, nil)
    |> assign(:report, nil)
    |> assign(:show_tracing_options, false)
    |> assign(:form, to_form(default_form_options()))
    |> assign(:form_search, to_form(default_form_search_options()))
  end

  def handle_mount(socket) do
    socket
    |> assign(:node_info, Selection.new())
    |> assign(:trace_session_id, nil)
    |> assign(:report, nil)
    |> assign(:show_tracing_options, false)
    |> assign(form: to_form(default_form_options()))
    |> assign(form_search: to_form(default_form_search_options()))
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Profiling")
  end

  @impl Page
  def handle_parent_event("toggle-options", _value, socket) do
    show_tracing_options = !socket.assigns.show_tracing_options

    {:noreply, assign(socket, :show_tracing_options, show_tracing_options)}
  end

  def handle_parent_event(
        "form-update",
        %{"max_messages" => max_messages, "session_timeout_seconds" => session_timeout_seconds},
        socket
      ) do
    {:noreply,
     assign(socket,
       form:
         to_form(%{
           "max_messages" => max_messages,
           "session_timeout_seconds" => session_timeout_seconds
         })
     )}
  end

  def handle_parent_event(
        "form-multi-select-list-update-search",
        %{"_target" => target} = values,
        socket
      ) do
    new_params = Enum.reduce(target, %{}, fn key, acc -> Map.put(acc, key, values[key]) end)

    form_search =
      socket.assigns.form_search.params
      |> Map.merge(new_params)
      |> to_form()

    {:noreply, assign(socket, form_search: form_search)}
  end

  def handle_parent_event(
        "profiling-stop",
        _data,
        %{assigns: %{trace_session_id: trace_session_id}} = socket
      ) do
    Tracer.stop_trace(trace_session_id)
    {:noreply, assign(socket, :trace_session_id, nil)}
  end

  def handle_parent_event(
        "profiling-run",
        _data,
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    tracer_state = Tracer.state()

    if tracer_state.status == :idle do
      functions_to_monitor = Selection.build_functions_to_monitor(node_info)

      case Tracer.start_trace(functions_to_monitor, %{
             max_messages: String.to_integer(form.params["max_messages"]),
             session_timeout_ms:
               String.to_integer(form.params["session_timeout_seconds"]) * 1_000,
             tool: :count
           }) do
        {:ok, %{session_id: session_id}} ->
          {:noreply,
           socket
           |> assign(:trace_session_id, session_id)
           |> assign(:report, nil)}

        # coveralls-ignore-start
        {:error, _} ->
          {:noreply, assign(socket, :trace_session_id, nil)}
          # coveralls-ignore-stop
      end
    else
      {:noreply, assign(socket, :trace_session_id, nil)}
    end
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      Selection.update(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "modules", "key" => module_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      Selection.update(
        node_info.selected_services_keys,
        node_info.selected_modules_keys -- [module_key],
        node_info.selected_functions_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "functions", "key" => function_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      Selection.update(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys -- [function_key]
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      Selection.update(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "modules", "key" => module_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      Selection.update(
        node_info.selected_services_keys,
        node_info.selected_modules_keys ++ [module_key],
        node_info.selected_functions_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "functions", "key" => function_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      Selection.update(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys ++ [function_key]
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  @impl Page
  def handle_info({:nodeup, _node}, %{assigns: %{node_info: node_info}} = socket) do
    node_info =
      Selection.update(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:nodedown, node}, %{assigns: %{node_info: node_info}} = socket) do
    service_key = node |> to_string

    node_info =
      Selection.update(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:tool_report, _session_id, report}, socket) do
    {:noreply, assign(socket, :report, report)}
  end

  def handle_info({event, _session_id}, socket)
      when event in [:trace_session_timeout, :stop_tracing] do
    {:noreply,
     socket
     |> assign(:trace_session_id, nil)
     |> assign(:show_tracing_options, false)}
  end

  defp default_form_options do
    %{
      "max_messages" => "1000",
      "session_timeout_seconds" => "30"
    }
  end

  defp default_form_search_options, do: %{"modules" => "", "functions" => ""}
end
