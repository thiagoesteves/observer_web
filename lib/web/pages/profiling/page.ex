defmodule Observer.Web.Profiling.Page do
  @moduledoc """
  This is the live component responsible for handling the Profiling tools (Count, Duration, Call
  Sequence and Flame Graph). Shares the node/module/function selection logic with
  `Observer.Web.Tracing.Page` via `Observer.Web.Tracing.Selection`, but runs its sessions with a
  `tool` selected instead of the raw match-spec picker, and shows a single aggregated report
  instead of a live event stream.
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

    tool = assigns.form.params["tool"] || "count"

    attention_msg =
      case tool do
        "duration" ->
          ~H"""
          Duration measures how long each traced function call takes. Like Live Tracing, it
          enforces limits on the maximum number of events and applies a timeout (in seconds) to
          ensure the debugger doesn't remain active unintentionally.
          """

        "call_seq" ->
          ~H"""
          Call Sequence shows an indented call tree per process, with arguments on entry and
          return values on exit. Like Live Tracing, it enforces limits on the maximum number of
          events and applies a timeout (in seconds) to ensure the debugger doesn't remain active
          unintentionally.
          """

        "flame_graph" ->
          ~H"""
          Flame Graph traces every call in the selected module(s) and shows how much time each
          process spent in each call stack, as a sunburst chart (one ring per stack depth). Like
          Live Tracing, it enforces limits on the maximum number of events and applies a timeout
          (in seconds) to ensure the debugger doesn't remain active unintentionally.
          """

        _count ->
          ~H"""
          Count tallies how many times each traced function was called. Like Live Tracing, it
          enforces limits on the maximum number of events and applies a timeout (in seconds) to
          ensure the debugger doesn't remain active unintentionally.
          """
      end

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_modules_keys: unselected_modules_keys)
      |> assign(unselected_functions_keys: unselected_functions_keys)
      |> assign(trace_idle?: trace_idle?)
      |> assign(trace_owner?: trace_owner?)
      |> assign(show_tracing_options: show_tracing_options)
      |> assign(attention_msg: attention_msg)
      |> assign(tool: tool)

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
              field={@form[:tool]}
              type="select"
              label="Tool"
              options={[
                {"Count", "count"},
                {"Duration", "duration"},
                {"Call Sequence", "call_seq"},
                {"Flame Graph", "flame_graph"}
              ]}
            />

            <Core.input
              :if={@tool == "duration"}
              field={@form[:aggregation]}
              type="select"
              label="Aggregation"
              options={[
                {"None (every call)", "none"},
                {"Sum", "sum"},
                {"Average", "avg"},
                {"Min", "min"},
                {"Max", "max"},
                {"Distribution", "dist"}
              ]}
            />

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
        <div :if={@report != nil} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded">
          <h2 class="px-4 pt-2 text-sm font-semibold text-gray-700 dark:text-gray-200">
            {result_title(@tool)}
          </h2>
          <Core.table_tracing
            :if={@tool not in ["call_seq", "flame_graph"]}
            id="profiling-results"
            rows={@report}
          >
            <:col :let={{{node, _mod, _fun, _arity, _message}, _value}} label="SERVICE">
              {node}
            </:col>
            <:col :let={{{_node, mod, fun, arity, _message}, _value}} label="FUNCTION">
              {inspect(mod)}.{fun}/{arity}
            </:col>
            <:col
              :let={{_key, value}}
              label={if @tool == "duration", do: "DURATION (µs)", else: "COUNT"}
            >
              {format_value(value)}
            </:col>
          </Core.table_tracing>
          <Core.table_tracing :if={@tool == "call_seq"} id="profiling-call-seq-results" rows={@report}>
            <:col :let={entry} label="SERVICE">{entry.node}</:col>
            <:col :let={entry} label="PROCESS">{inspect(entry.pid)}</:col>
            <:col :let={entry} label="CALL">
              <span style={"padding-left: #{entry.depth * 1.25}rem"}>
                <%= if entry.type == :enter do %>
                  → {inspect(entry.mod)}.{entry.fun}/{entry.arity}({format_args(entry.detail)})
                <% else %>
                  ← {inspect(entry.mod)}.{entry.fun}/{entry.arity} = {inspect(entry.detail)}
                <% end %>
              </span>
            </:col>
          </Core.table_tracing>
          <div
            :if={@tool == "flame_graph"}
            id="profiling-flame-graph"
            class="ml-5 mr-5 mt-2"
            phx-hook="ObserverEChart"
            data-merge={false}
          >
            <div
              id="profiling-flame-graph-chart"
              style="width: 100%; height: 600px;"
              phx-update="ignore"
            />
            <div id="profiling-flame-graph-data" hidden>
              {Jason.encode!(sunburst_chart_data(@report))}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ObserverEChart (shared with Observer.Web.Apps.Page's tree chart) always pushes this event on
  # tooltip render so its host can drill into the hovered node - the Flame Graph sunburst has no
  # such drill-down, but without a matching handle_event/3 clause here the hook would crash this
  # LiveComponent (no default/fallback clause exists) the first time a user hovers over it.
  @impl Phoenix.LiveComponent
  def handle_event("request-process", _params, socket), do: {:noreply, socket}

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

  def handle_parent_event("form-update", params, socket) do
    {:noreply, assign(socket, form: to_form(params))}
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
      tool = tool_atom(form.params["tool"])

      case Tracer.start_trace(functions_to_monitor, %{
             max_messages: String.to_integer(form.params["max_messages"]),
             session_timeout_ms:
               String.to_integer(form.params["session_timeout_seconds"]) * 1_000,
             tool: tool,
             tool_opts: %{aggregation: aggregation_opt(form.params["aggregation"])}
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
      "tool" => "count",
      "aggregation" => "none",
      "max_messages" => "100",
      "session_timeout_seconds" => "30"
    }
  end

  # `String.to_existing_atom/1` requires the target atom to already be interned in the VM, which
  # only happens once the module that mentions it as a literal (`ObserverWeb.Tracer.Tool`,
  # `ObserverWeb.Tracer.Tool.Duration`) has actually been loaded - normally by an earlier trace
  # session. On a freshly booted node, using one of these tools/aggregations for the very first
  # time would otherwise crash with `ArgumentError: not an already existing atom`. Mapping from the
  # fixed, known set of values our own `<Core.input type="select">` options offer (not arbitrary
  # user input) sidesteps that entirely, since the atom literals below are guaranteed to already
  # exist as soon as this module itself is loaded.
  @spec tool_atom(String.t() | nil) :: ObserverWeb.Tracer.Tool.t()
  defp tool_atom("duration"), do: :duration
  defp tool_atom("call_seq"), do: :call_seq
  defp tool_atom("flame_graph"), do: :flame_graph
  defp tool_atom(_count), do: :count

  defp aggregation_opt(aggregation) when aggregation in [nil, "", "none"], do: nil
  defp aggregation_opt("sum"), do: :sum
  defp aggregation_opt("avg"), do: :avg
  defp aggregation_opt("min"), do: :min
  defp aggregation_opt("max"), do: :max
  defp aggregation_opt("dist"), do: :dist

  defp default_form_search_options, do: %{"modules" => "", "functions" => ""}

  defp result_title("duration"), do: "Duration Results"
  defp result_title("call_seq"), do: "Call Sequence Results"
  defp result_title("flame_graph"), do: "Flame Graph Results"
  defp result_title(_count), do: "Count Results"

  defp sunburst_chart_data(report) do
    %{
      tooltip: %{
        trigger: "item",
        triggerOn: "mousemove",
        formatter: "{b}: {c}µs"
      },
      series: [
        %{
          type: "sunburst",
          radius: [0, "95%"],
          data: report,
          label: %{rotate: "radial"},
          emphasis: %{focus: "ancestor"}
        }
      ]
    }
  end

  # The :dist aggregation reports a %{bucket => count} power-of-two histogram (see
  # ObserverWeb.Tracer.Tool.Duration) - render it as readable ranges instead of an inspected map.
  defp format_value(value) when is_map(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join(", ", fn {bucket, count} ->
      upper = if bucket == 0, do: 1, else: bucket * 2
      "#{bucket}-#{upper}µs: #{count}"
    end)
  end

  defp format_value(value), do: inspect(value)

  defp format_args(args) when is_list(args), do: Enum.map_join(args, ", ", &inspect/1)
  defp format_args(other), do: inspect(other)
end
