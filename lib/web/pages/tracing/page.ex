defmodule Observer.Web.Tracing.Page do
  @moduledoc """
  This is the live component responsible for handling the Tracing debug
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.CopyToClipboard
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

    unselected_match_spec_keys =
      assigns.node_info.match_spec_keys -- assigns.node_info.selected_match_spec_keys

    trace_state = Tracer.state()

    trace_idle? = trace_state.status == :idle
    trace_owner? = trace_state.session_id == assigns.trace_session_id

    # Hide options when running
    show_tracing_options = trace_idle? and trace_owner? and assigns.show_tracing_options

    match_spec_info = ~H"""
    <a
      href="https://www.erlang.org/docs/24/apps/erts/match_spec"
      class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
    >
      (more_info)
    </a>
    """

    attention_msg = ~H"""
    Incorrect use of the <b>:dbg</b>
    tracer in production can lead to performance degradation, latency and crashes.
    <b>Observer Web tracing</b>
    enforces limits on the maximum number of messages and applies a timeout (in seconds)
    to ensure the debugger doesn't remain active unintentionally. Check out the
    <a
      href="https://www.erlang.org/docs/24/man/dbg"
      class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
    >
      Erlang Debugger
    </a>
    for more detailed information.
    """

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_modules_keys: unselected_modules_keys)
      |> assign(unselected_functions_keys: unselected_functions_keys)
      |> assign(unselected_match_spec_keys: unselected_match_spec_keys)
      |> assign(match_spec_info: match_spec_info)
      |> assign(trace_idle?: trace_idle?)
      |> assign(trace_idle?: trace_idle?)
      |> assign(trace_owner?: trace_owner?)
      |> assign(show_tracing_options: show_tracing_options)
      |> assign(attention_msg: attention_msg)

    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="tracing"
        title="Attention"
        class="border-red-400 dark:border-red-700 text-red-500 dark:text-red-200"
        message={@attention_msg}
      >
        <:inner_form>
          <.form
            for={@form}
            id="tracing-update-form"
            class="flex ml-2 mr-2 text-xs text-center text-zinc-800 dark:text-white  whitespace-nowrap gap-5"
            phx-change="form-update"
          >
            <Core.input
              field={@form[:max_messages]}
              type="number"
              step="1"
              min="1"
              max="50"
              label="Messages"
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
            id="tracing-multi-select-run"
            phx-click="tracing-apps-run"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 dark:bg-green-700 transform active:scale-75 transition-transform hover:bg-green-800 dark:hover:bg-green-800 py-10 w-64 text-sm font-semibold text-white active:text-white/80"
          >
            RUN
          </button>
          <button
            :if={@trace_idle? == false and @trace_owner?}
            id="tracing-multi-select-stop"
            phx-click="tracing-apps-stop"
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
          id="tracing-multi-select"
          selected_text="Selected Items"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "modules", keys: @node_info.selected_modules_keys},
            %{name: "functions", keys: @node_info.selected_functions_keys},
            %{name: "match_spec", keys: @node_info.selected_match_spec_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "modules", keys: @unselected_modules_keys},
            %{name: "functions", keys: @unselected_functions_keys},
            %{name: "match_spec", keys: @unselected_match_spec_keys, info: @match_spec_info}
          ]}
          show_options={@show_tracing_options}
          form_search={@form_search}
        />
      </div>
      <div class="p-2">
        <div
          :if={not @trace_messages? and @trace_idle?}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Select functions to trace and press RUN to stream calls live.
        </div>
        <div
          :if={not @trace_messages? and not @trace_idle?}
          class="p-4 text-sm text-gray-500 dark:text-gray-400"
        >
          Waiting for trace messages...
        </div>
        <div :if={@trace_messages?} class="bg-white dark:bg-gray-800 w-full shadow-lg rounded">
          <Core.table_tracing id="live-logs" rows={@streams.tracing_messages}>
            <:col :let={{_id, tracing_message}} label="SERVICE">
              <span>{tracing_message.service}</span>
            </:col>
            <:col :let={{_id, tracing_message}} label="INDEX">
              <span>{tracing_message.index}</span>
            </:col>
            <:col :let={{_id, tracing_message}} label="TYPE">
              <span>{tracing_message.type}</span>
            </:col>
            <:col :let={{id, tracing_message}} label="CONTENT">
              <details>
                <summary class="cursor-pointer truncate">
                  {tracing_message.content}
                </summary>
                <div class="mt-5 break-words">
                  <div class="flex items-center justify-between gap-2">
                    {tracing_message.content}

                    <CopyToClipboard.content
                      id={"tracing-functions-messages-#{id}"}
                      message={tracing_message.content}
                    />
                  </div>
                </div>
              </details>
            </:col>
          </Core.table_tracing>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) when is_connected?(socket) do
    # Subscribe to notifications if any node is UP or Down
    :net_kernel.monitor_nodes(true)

    socket
    |> assign(:node_info, update_node_info())
    |> assign(:node_data, %{})
    |> assign(:trace_session_id, nil)
    |> assign(:trace_messages?, false)
    |> assign(:show_tracing_options, false)
    |> assign(:form, to_form(default_form_options()))
    |> assign(:form_search, to_form(default_form_search_options()))
    |> stream(:tracing_messages, [])
  end

  def handle_mount(socket) do
    socket
    |> assign(:node_info, node_info_new())
    |> assign(:node_data, %{})
    |> assign(:trace_session_id, nil)
    |> assign(:trace_messages?, false)
    |> assign(:show_tracing_options, false)
    |> assign(form: to_form(default_form_options()))
    |> assign(form_search: to_form(default_form_search_options()))
    |> stream(:tracing_messages, [])
  end

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Live Tracing")
  end

  @impl Page
  def handle_parent_event("toggle-options", _value, socket) do
    show_tracing_options = !socket.assigns.show_tracing_options

    {:noreply, socket |> assign(:show_tracing_options, show_tracing_options)}
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
        "tracing-apps-stop",
        _data,
        %{assigns: %{trace_session_id: trace_session_id}} = socket
      ) do
    Tracer.stop_trace(trace_session_id)
    {:noreply, assign(socket, :trace_session_id, nil)}
  end

  def handle_parent_event(
        "tracing-apps-run",
        _data,
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    tracer_state = Tracer.state()

    if tracer_state.status == :idle do
      functions_to_monitor =
        Selection.build_functions_to_monitor(node_info, node_info.selected_match_spec_keys)

      case Tracer.start_trace(functions_to_monitor, %{
             max_messages: String.to_integer(form.params["max_messages"]),
             session_timeout_ms: String.to_integer(form.params["session_timeout_seconds"]) * 1_000
           }) do
        {:ok, %{session_id: session_id}} ->
          {:noreply,
           socket
           |> assign(:trace_session_id, session_id)
           |> assign(:trace_messages?, false)
           |> stream(:tracing_messages, [], reset: true)}

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
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "modules", "key" => module_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys -- [module_key],
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "functions", "key" => function_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys -- [function_key],
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "match_spec", "key" => match_spec_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys -- [match_spec_key]
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "modules", "key" => module_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys ++ [module_key],
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "functions", "key" => function_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys ++ [function_key],
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "match_spec", "key" => match_spec_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys ++ [match_spec_key]
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  @impl Page
  def handle_info({:nodeup, _node}, %{assigns: %{node_info: node_info}} = socket) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:nodedown, node}, %{assigns: %{node_info: node_info}} = socket) do
    service_key = node |> to_string

    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:new_trace_message, _session_id, node, index, type, message}, socket) do
    data = %{
      service: node,
      id: ObserverWeb.Common.uuid4(),
      index: index,
      type: type,
      content: message
    }

    {:noreply,
     socket
     |> assign(:trace_messages?, true)
     |> stream(:tracing_messages, [data])}
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
      "max_messages" => "3",
      "session_timeout_seconds" => "30"
    }
  end

  defp default_form_search_options, do: %{"modules" => "", "functions" => ""}

  defp node_info_new do
    Selection.new()
    |> Map.put(:match_spec_keys, default_match_spec_keys())
    |> Map.put(:selected_match_spec_keys, [])
  end

  defp update_node_info, do: update_node_info([], [], [], [])

  defp update_node_info(
         selected_services_keys,
         selected_modules_keys,
         selected_functions_keys,
         selected_match_spec_keys
       ) do
    selected_services_keys
    |> Selection.update(selected_modules_keys, selected_functions_keys)
    |> Map.put(:match_spec_keys, default_match_spec_keys())
    |> Map.put(:selected_match_spec_keys, selected_match_spec_keys)
  end

  defp default_match_spec_keys do
    Tracer.get_default_functions_matchspecs() |> Map.keys() |> Enum.sort()
  end
end
