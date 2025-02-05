defmodule Observer.Web.Tracing.Page do
  @moduledoc """
  This is the live component responsible for handling the Tracing debug
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Components.MultiSelectList
  alias Observer.Web.Page
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
    <b>Observer Web tracing</b> enforces limits on the maximum number of messages and applies a timeout (in seconds)
    to ensure the debugger doesn't remain active unintentionally. Check out the
    <a
      href="https://www.erlang.org/docs/24/man/dbg"
      class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
    >
      Erlang Debugger
    </a> for more detailed information.
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
    <div class="min-h-screen bg-white">
      <Attention.content
        id="tracing"
        title="Attention"
        class="border-red-400 text-red-500"
        message={@attention_msg}
      >
        <:inner_form>
          <.form
            for={@form}
            id="tracing-update-form"
            class="flex ml-2 mr-2 text-xs text-center whitespace-nowrap gap-5"
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
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 transform active:scale-75 transition-transform hover:bg-green-600 py-10 w-64 text-sm font-semibold  text-white active:text-white/80"
          >
            RUN
          </button>
          <button
            :if={@trace_idle? == false and @trace_owner?}
            id="tracing-multi-select-stop"
            phx-click="tracing-apps-stop"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-red-500 transform active:scale-75 transition-transform hover:bg-red-600 py-10 w-64 text-sm font-semibold text-white active:text-white/80 animate-pulse"
          >
            STOP
          </button>

          <button
            :if={not @trace_owner?}
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-red-500 transform active:scale-75 transition-transform hover:bg-red-600 py-10 w-64 text-sm font-semibold text-white active:text-white/80 animate-pulse"
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
        />
      </div>
      <div class="p-2">
        <div class="bg-white w-full shadow-lg rounded">
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
            <:col :let={{_id, tracing_message}} label="CONTENT">
              {tracing_message.content}
            </:col>
          </Core.table_tracing>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) do
    socket
    |> assign(:node_info, update_node_info())
    |> assign(:node_data, %{})
    |> assign(:trace_session_id, nil)
    |> assign(:show_tracing_options, false)
    |> assign(:form, to_form(default_form_options()))
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
        Enum.reduce(node_info.selected_services_keys, [], fn service_key, service_acc ->
          service_info = Enum.find(node_info.node, &(&1.service == service_key))

          service_acc ++
            Enum.reduce(node_info.selected_modules_keys, [], fn module_key, module_acc ->
              module_key_atom = String.to_existing_atom(module_key)

              node_functions_info =
                Enum.find(service_info.functions, &(&1.module == module_key_atom))

              functions =
                Enum.reduce(node_info.selected_functions_keys, [], fn function_key,
                                                                      function_acc ->
                  function = Map.get(node_functions_info.functions, function_key, nil)

                  # credo:disable-for-lines:14
                  if module_key in service_info.modules_keys and function do
                    function_acc ++
                      [
                        %{
                          node: String.to_existing_atom(service_key),
                          module: module_key_atom,
                          function: function.name,
                          arity: function.arity,
                          match_spec: node_info.selected_match_spec_keys
                        }
                      ]
                  else
                    function_acc
                  end
                end)

              # If the module doesn't have any of the requested functions the default is to
              # include the whole module
              if functions == [] do
                module_acc ++
                  [
                    %{
                      node: String.to_existing_atom(service_key),
                      module: module_key_atom,
                      function: :_,
                      arity: :_,
                      match_spec: node_info.selected_match_spec_keys
                    }
                  ]
              else
                module_acc ++ functions
              end
            end)
        end)

      case Tracer.start_trace(functions_to_monitor, %{
             max_messages: String.to_integer(form.params["max_messages"]),
             session_timeout_ms: String.to_integer(form.params["session_timeout_seconds"]) * 1_000
           }) do
        {:ok, %{session_id: session_id}} ->
          {:noreply,
           socket
           |> assign(:trace_session_id, session_id)
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

    {:noreply, stream(socket, :tracing_messages, [data])}
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

  defp node_info_new do
    match_spec_keys =
      Tracer.get_default_functions_matchspecs()
      |> Map.keys()
      |> Enum.sort()

    %{
      services_keys: [],
      modules_keys: [],
      functions_keys: [],
      match_spec_keys: match_spec_keys,
      selected_services_keys: [],
      selected_modules_keys: [],
      selected_functions_keys: [],
      selected_match_spec_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [], [], [])

  defp update_node_info(
         selected_services_keys,
         selected_modules_keys,
         selected_functions_keys,
         selected_match_spec_keys
       ) do
    initial_map =
      %{
        node_info_new()
        | selected_services_keys: selected_services_keys,
          selected_modules_keys: selected_modules_keys,
          selected_functions_keys: selected_functions_keys,
          selected_match_spec_keys: selected_match_spec_keys
      }

    Enum.reduce(Node.list() ++ [Node.self()], initial_map, fn instance_node,
                                                              %{
                                                                services_keys: services_keys,
                                                                modules_keys: modules_keys,
                                                                functions_keys: functions_keys,
                                                                match_spec_keys: match_spec_keys,
                                                                node: node
                                                              } = acc ->
      service = instance_node |> to_string
      service_selected? = service in selected_services_keys

      [name, _hostname] = String.split(service, "@")
      services_keys = (services_keys ++ [service]) |> Enum.sort()

      instance_module_keys =
        if service_selected? do
          Tracer.get_modules(instance_node) |> Enum.map(&to_string/1)
        else
          []
        end

      {instance_functions_keys, functions} =
        Enum.reduce(instance_module_keys, {[], []}, fn module, {keys, fun} ->
          # credo:disable-for-lines:6
          if module in selected_modules_keys do
            module_functions_info =
              Tracer.get_module_functions_info(instance_node, String.to_existing_atom(module))

            function_keys = Map.keys(module_functions_info.functions) |> Enum.map(&to_string/1)
            {keys ++ function_keys, fun ++ [module_functions_info]}
          else
            {keys, fun}
          end
        end)

      modules_keys = (modules_keys ++ instance_module_keys) |> Enum.sort() |> Enum.uniq()
      functions_keys = (functions_keys ++ instance_functions_keys) |> Enum.sort() |> Enum.uniq()

      node =
        if service_selected? do
          [
            %{
              name: name,
              modules_keys: instance_module_keys,
              function_keys: instance_functions_keys,
              match_spec_keys: match_spec_keys,
              service: service,
              functions: functions
            }
            | node
          ]
        else
          node
        end

      %{
        acc
        | services_keys: services_keys,
          modules_keys: modules_keys,
          functions_keys: functions_keys,
          match_spec_keys: match_spec_keys,
          node: node
      }
    end)
  end
end
