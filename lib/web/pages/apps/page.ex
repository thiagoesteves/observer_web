defmodule Observer.Web.Apps.Page do
  @moduledoc """
  This is the live component responsible for handling the Observer page
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias Observer.Web.Apps.Legend
  alias Observer.Web.Apps.Port
  alias Observer.Web.Apps.Process
  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Confirm
  alias Observer.Web.Components.MultiSelect
  alias Observer.Web.Helpers
  alias Observer.Web.Page
  alias ObserverWeb.Apps

  @tooltip_debouncing 50

  @impl Phoenix.LiveComponent
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_apps_keys =
      assigns.node_info.apps_keys -- assigns.node_info.selected_apps_keys

    # credo:disable-for-lines:9
    adjust_series_position = fn series ->
      case Enum.count(series) do
        n when n > 0 ->
          step = 100.0 / n

          {series, _top, _bottom} =
            Enum.reduce(series, {[], 0.0, 100.0}, fn serie, {acc, top, bottom} ->
              bottom = bottom - step

              new_serie = %{
                serie
                | top: :erlang.float_to_binary(top, [{:decimals, 0}]) <> "%",
                  bottom: :erlang.float_to_binary(bottom, [{:decimals, 0}]) <> "%"
              }

              {acc ++ [new_serie], top + step, bottom}
            end)

          series

        _ ->
          series
      end
    end

    initial_tree_depth = assigns.form.params["initial_tree_depth"]

    chart_tree_data =
      assigns.observer_data
      |> Enum.reduce([], fn {key, %{"data" => info}}, acc ->
        acc ++ [series(key, info, initial_tree_depth)]
      end)
      |> adjust_series_position.()
      |> flare_chart_data()

    attention_msg = ~H"""
    The <b>Observer Web </b> visualizes process relationships, supervisor trees, and more.
    Hover over an element to view detailed information about the process or port.
    You can also configure the initial tree depth, or set the depth to <b>-1</b> to expand all trees.
    """

    assigns =
      assigns
      |> assign(chart_tree_data: chart_tree_data)
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_apps_keys: unselected_apps_keys)
      |> assign(attention_msg: attention_msg)

    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800">
      <Attention.content
        id="observer"
        title="Information"
        class="border-blue-400 dark:border-blue-700 text-blue-500 dark:text-blue-200"
        message={@attention_msg}
      >
        <:inner_form>
          <.form
            for={@form}
            id="apps-update-form"
            class="flex ml-2 mr-2 text-xs text-center text-zinc-800 dark:text-white whitespace-nowrap gap-5"
            phx-change="form-update"
          >
            <Core.input
              field={@form[:initial_tree_depth]}
              type="number"
              step="1"
              min="-1"
              label="Initial Depth"
            />
            <Core.input
              field={@form[:get_state_timeout]}
              type="number"
              step="100"
              min="100"
              label="State Timeout (ms)"
            />
          </.form>
        </:inner_form>
        <:inner_button>
          <button
            id="apps-multi-select-update"
            phx-click="apps-apps-update"
            class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 transform active:scale-75 transition-transform hover:bg-green-600 py-10 w-64 text-sm font-semibold  text-white active:text-white/80"
          >
            UPDATE
          </button>
        </:inner_button>
      </Attention.content>

      <div class="flex">
        <MultiSelect.content
          id="apps-multi-select"
          selected_text="Selected apps"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "apps", keys: @node_info.selected_apps_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys, unselected_highlight: []},
            %{name: "apps", keys: @unselected_apps_keys, unselected_highlight: []}
          ]}
          show_options={@show_observer_options}
        />
      </div>
      <div class="p-2">
        <%= if @observer_data != %{}  do %>
          <Legend.content />
        <% end %>
        <div>
          <div id="apps-tree" class="ml-5 mr-5 mt-10" phx-hook="ObserverEChart" data-merge={false}>
            <div id="apps-tree-chart" style="width: 100%; height: 600px;" phx-update="ignore" />
            <div id="apps-tree-data" hidden>{Jason.encode!(@chart_tree_data)}</div>
          </div>
        </div>
        <%= if @current_selected_id.type == "pid" do %>
          <Process.content
            id={@current_selected_id.id_string}
            form={@process_msg_form}
            info={@current_selected_id.info}
            process_memory_monitor={@process_memory_monitor}
          />
        <% else %>
          <Port.content id={@current_selected_id.id_string} info={@current_selected_id.info} />
        <% end %>
      </div>

      <%= if @process_kill_confirmation do %>
        <Confirm.content id={"process-kill-modal-#{@current_selected_id.id_string}"}>
          <:header>
            <p>Attention</p>
          </:header>
          <p>
            Are you sure you want to restart process pid: {"#{@current_selected_id.id_string}"}?
          </p>
          <:footer>
            <Confirm.cancel_button id={Helpers.pid_string_to_safe_id(@current_selected_id.id_string)}>
              Cancel
            </Confirm.cancel_button>
            <Confirm.confirm_button
              event="process-kill-confirmation"
              id={Helpers.pid_string_to_safe_id(@current_selected_id.id_string)}
              value={@current_selected_id.id_string}
            >
              Confirm
            </Confirm.confirm_button>
          </:footer>
        </Confirm.content>
      <% end %>
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
    |> assign(:observer_data, %{})
    |> assign(:current_selected_id, reset_current_selected_id())
    |> assign(form: to_form(default_form_options()))
    |> assign(process_msg_form: to_form(%{"message" => ""}))
    |> assign(:show_observer_options, false)
    |> assign(:process_memory_monitor, false)
    |> assign(:process_kill_confirmation, false)
  end

  def handle_mount(socket) do
    socket
    |> assign(:node_info, node_info_new())
    |> assign(:node_data, %{})
    |> assign(:observer_data, %{})
    |> assign(:current_selected_id, reset_current_selected_id())
    |> assign(form: to_form(default_form_options()))
    |> assign(process_msg_form: to_form(%{"message" => ""}))
    |> assign(:show_observer_options, false)
    |> assign(:process_memory_monitor, false)
    |> assign(:process_kill_confirmation, false)
  end

  # coveralls-ignore-start
  @impl Phoenix.LiveComponent
  def handle_event(message, value, socket) do
    # Redirect message to the parent process
    # Testing is not possible since there is no mechanism to send a message to a component
    send(self(), {message, value})
    {:noreply, socket}
  end

  # coveralls-ignore-stop

  @impl Page
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Live Applications")
  end

  @impl Page
  def handle_parent_event("toggle-options", _value, socket) do
    show_observer_options = !socket.assigns.show_observer_options

    {:noreply, socket |> assign(:show_observer_options, show_observer_options)}
  end

  def handle_parent_event("request_process_action", %{"action" => "kill"}, socket) do
    {:noreply, assign(socket, :process_kill_confirmation, true)}
  end

  def handle_parent_event(
        "request_process_action",
        %{"action" => "garbage_collect"},
        %{assigns: %{current_selected_id: current_selected_id}} = socket
      ) do
    pid_string = current_selected_id.id_string
    true = pid_string |> Helpers.string_to_pid() |> :erlang.garbage_collect()

    {:noreply,
     socket
     |> put_flash(:info, "Process pid: #{pid_string} successfully garbage collected")}
  end

  def handle_parent_event(
        "request_process_action",
        %{"process-send-message" => message},
        %{assigns: %{current_selected_id: current_selected_id}} = socket
      ) do
    pid_string = current_selected_id.id_string
    pid = Helpers.string_to_pid(pid_string)

    {term, _} = Code.eval_string(message)
    send(pid, term)

    {:noreply,
     socket
     |> put_flash(:info, "Message sent to process pid: #{pid_string} with success")}
  end

  def handle_parent_event(
        "request_process_action",
        _params,
        %{
          assigns: %{
            current_selected_id: current_selected_id,
            process_memory_monitor: process_memory_monitor
          }
        } = socket
      ) do
    new_process_memory_monitor = !process_memory_monitor
    text = if new_process_memory_monitor, do: "enabled", else: "disabled"
    pid_string = current_selected_id.id_string

    # NOTE: Add monitor enable actions here

    {:noreply,
     socket
     |> assign(:process_memory_monitor, new_process_memory_monitor)
     |> put_flash(:info, "Memory monitoring #{text} for process pid: #{pid_string}")}
  end

  def handle_parent_event(
        "process-message-form-update",
        %{"process-send-message" => message},
        socket
      ) do
    # NOTE: Validate that the message is valid Elixir syntax by attempting to parse and evaluate it
    errors =
      try do
        case Code.eval_string(message) do
          {_term, _} ->
            []
        end
      rescue
        _exception ->
          [{:message, {"invalid elixir format", []}}]
      end

    {:noreply, assign(socket, process_msg_form: to_form(%{"message" => message}, errors: errors))}
  end

  def handle_parent_event("process-kill-confirmation", %{"id" => pid_string}, socket) do
    true = pid_string |> Helpers.string_to_pid() |> Elixir.Process.exit(:kill)

    {:noreply,
     socket
     |> assign(:process_kill_confirmation, false)
     |> put_flash(:info, "Process pid: #{pid_string} successfully terminated")
     |> assign(:current_selected_id, reset_current_selected_id())}
  end

  def handle_parent_event("confirm-close-modal", _, socket) do
    {:noreply, assign(socket, :process_kill_confirmation, false)}
  end

  def handle_parent_event(
        "form-update",
        %{"initial_tree_depth" => depth, "get_state_timeout" => get_state_timeout},
        socket
      ) do
    {:noreply,
     assign(socket,
       form: to_form(%{"initial_tree_depth" => depth, "get_state_timeout" => get_state_timeout})
     )}
  end

  def handle_parent_event(
        "apps-apps-update",
        _data,
        %{assigns: %{observer_data: observer_data}} = socket
      ) do
    new_observer_data =
      Enum.reduce(observer_data, %{}, fn {key, data}, acc ->
        [service, app] = String.split(key, "::")

        new_info =
          Apps.info(String.to_existing_atom(service), String.to_existing_atom(app))

        Map.put(acc, key, %{data | "data" => new_info})
      end)

    {:noreply,
     socket
     |> assign(:observer_data, new_observer_data)}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_apps_keys
      )

    socket =
      Enum.reduce(node_info.selected_apps_keys, socket, fn app_key, acc ->
        data_key = data_key(service_key, app_key)

        update_observer_data(acc, data_key, nil)
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_id, reset_current_selected_id())}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "apps", "key" => app_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_apps_keys -- [app_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        data_key = data_key(service_key, app_key)

        update_observer_data(acc, data_key, nil)
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_id, reset_current_selected_id())}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_apps_keys
      )

    socket =
      Enum.reduce(node_info.selected_apps_keys, socket, fn app_key, acc ->
        node_service = Enum.find(node_info.node, &(&1.service == service_key))

        data_key = data_key(service_key, app_key)

        if app_key in node_service.apps_keys do
          info =
            Apps.info(
              String.to_existing_atom(service_key),
              String.to_existing_atom(app_key)
            )

          update_observer_data(acc, data_key, %{"transition" => false, "data" => info})
        else
          # coveralls-ignore-start
          update_observer_data(acc, data_key, nil)
          # coveralls-ignore-stop
        end
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_id, reset_current_selected_id())}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "apps", "key" => app_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_apps_keys ++ [app_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        node_service = Enum.find(node_info.node, &(&1.service == service_key))

        data_key = data_key(service_key, app_key)

        if app_key in node_service.apps_keys do
          info =
            Apps.info(
              String.to_existing_atom(service_key),
              String.to_existing_atom(app_key)
            )

          update_observer_data(acc, data_key, %{"transition" => false, "data" => info})
        else
          # coveralls-ignore-start
          update_observer_data(acc, data_key, nil)
          # coveralls-ignore-stop
        end
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_id, reset_current_selected_id())}
  end

  @impl Page
  def handle_info(
        {"request-process", %{"id" => request_id, "series_name" => series_name}},
        %{
          assigns: %{
            current_selected_id: %{id_string: id_string, debouncing: debouncing},
            form: form
          }
        } =
          socket
      )
      when id_string != request_id or debouncing < 0 do
    get_state_timeout = form.params["get_state_timeout"] |> String.to_integer()

    current_selected_id =
      case Helpers.parse_identifier(request_id) do
        {:pid, pid} ->
          %{
            info: Apps.Process.info(pid, get_state_timeout),
            id_string: request_id,
            type: "pid",
            debouncing: @tooltip_debouncing
          }

        {:port, port} ->
          [service, _app] = String.split(series_name, "::")
          node = String.to_existing_atom(service)

          %{
            info: Apps.Port.info(node, port),
            id_string: request_id,
            type: "port",
            debouncing: @tooltip_debouncing
          }

        {:none, _any} ->
          reset_current_selected_id(request_id)
      end

    {:noreply, assign(socket, :current_selected_id, current_selected_id)}
  end

  # The debouncing added here will reduce the number of Process.info requests since
  # tooltips are high demand signals.
  def handle_info(
        {"request-process", _data},
        %{assigns: %{current_selected_id: current_selected_id}} = socket
      ) do
    {:noreply,
     assign(socket, :current_selected_id, %{
       current_selected_id
       | debouncing: current_selected_id.debouncing - 1
     })}
  end

  def handle_info({:nodeup, _node}, %{assigns: %{node_info: node_info}} = socket) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_apps_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:nodedown, node}, %{assigns: %{node_info: node_info}} = socket) do
    service_key = node |> to_string

    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_apps_keys
      )

    socket =
      Enum.reduce(node_info.selected_apps_keys, socket, fn app_key, acc ->
        data_key = data_key(service_key, app_key)

        update_observer_data(acc, data_key, nil)
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_id, reset_current_selected_id())}
  end

  defp data_key(service, apps), do: "#{service}::#{apps}"

  defp update_observer_data(
         %{assigns: %{observer_data: observer_data}} = socket,
         data_key,
         nil
       ) do
    assign(socket, :observer_data, Map.delete(observer_data, data_key))
  end

  defp update_observer_data(
         %{assigns: %{observer_data: observer_data}} = socket,
         data_key,
         attributes
       ) do
    updated_data =
      observer_data
      |> Map.get(data_key, %{})
      |> Map.merge(attributes)

    assign(socket, :observer_data, Map.put(observer_data, data_key, updated_data))
  end

  defp default_form_options, do: %{"initial_tree_depth" => "3", "get_state_timeout" => "100"}

  defp node_info_new do
    %{
      services_keys: [],
      apps_keys: [],
      selected_services_keys: [],
      selected_apps_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services_keys, selected_apps_keys) do
    initial_map =
      %{
        node_info_new()
        | selected_services_keys: selected_services_keys,
          selected_apps_keys: selected_apps_keys
      }

    Enum.reduce(Node.list() ++ [Node.self()], initial_map, fn instance_node,
                                                              %{
                                                                services_keys: services_keys,
                                                                apps_keys: apps_keys,
                                                                node: node
                                                              } = acc ->
      service = instance_node |> to_string
      [name, _hostname] = String.split(service, "@")
      services_keys = (services_keys ++ [service]) |> Enum.sort()

      instance_app_keys = Apps.list(instance_node) |> Enum.map(&(&1.name |> to_string))
      apps_keys = (apps_keys ++ instance_app_keys) |> Enum.sort() |> Enum.uniq()

      node =
        if service in selected_services_keys do
          [
            %{
              name: name,
              apps_keys: instance_app_keys,
              service: service
            }
            | node
          ]
        else
          node
        end

      %{acc | services_keys: services_keys, apps_keys: apps_keys, node: node}
    end)
  end

  defp reset_current_selected_id(id_string \\ nil),
    do: %{info: nil, id_string: id_string, type: nil, debouncing: @tooltip_debouncing}

  defp flare_chart_data(series) do
    %{
      tooltip: %{
        trigger: "item",
        triggerOn: "mousemove"
      },
      notMerge: true,
      legend: [
        %{
          top: "5%",
          left: "0%",
          orient: "vertical",
          borderColor: "#c23531"
        }
      ],
      series: series
    }
  end

  defp series(name, data, initial_tree_depth) do
    %{
      type: "tree",
      name: name,
      data: [data],
      top: "0%",
      left: "30%",
      bottom: "74%",
      right: "20%",
      symbolSize: 10,
      itemStyle: %{color: "#93C5FD"},
      edgeShape: "curve",
      edgeForkPosition: "63%",
      initialTreeDepth: initial_tree_depth,
      lineStyle: %{
        width: 2
      },
      axisPointer: [
        %{
          show: "auto"
        }
      ],
      label: %{
        backgroundColor: "#fff",
        position: "top",
        verticalAlign: "middle",
        align: "center"
      },
      leaves: %{
        label: %{
          position: "right",
          verticalAlign: "middle",
          align: "left"
        }
      },
      emphasis: %{
        focus: "descendant"
      },
      roam: "zoom",
      symbol: "emptyCircle",
      expandAndCollapse: true,
      animationDuration: 550,
      animationDurationUpdate: 750
    }
  end
end
