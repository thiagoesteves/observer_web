defmodule Observer.Web.Metrics.Page do
  @moduledoc """
  This is the live component responsible for handling the Live Metrics
  """

  @behaviour Observer.Web.Page

  use Observer.Web, :live_component

  alias ObserverWeb.Telemetry
  alias Observer.Web.Components.Metrics.VmMemory
  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.Core
  alias Observer.Web.Components.MultiSelect
  alias Observer.Web.Page

  @impl Phoenix.LiveComponent
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_metrics_keys =
      assigns.node_info.metrics_keys -- assigns.node_info.selected_metrics_keys

    attention_msg = ~H"""
    """

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_metrics_keys: unselected_metrics_keys)
      |> assign(attention_msg: attention_msg)

    ~H"""
    <div class="min-h-screen bg-white">
      <Attention.content
        id="metrics"
        title="Configuration"
        class="border-orange-400 text-orange-500"
        message={@attention_msg}
      >
        <:inner_form>
          <.form
            for={@form}
            id="metrics-update-form"
            class="flex ml-2 mr-2 text-xs text-center text-black whitespace-nowrap gap-5"
            phx-change="form-update"
          >
            <Core.input
              field={@form[:num_cols]}
              type="select"
              label="Column Size"
              options={["1", "2", "3", "4"]}
            />
            <Core.input
              field={@form[:start_time]}
              type="select"
              label="Start Time"
              options={["1 minute", "5 minutes", "15 minutes", "30 minutes"]}
            />
          </.form>
        </:inner_form>
      </Attention.content>
      <div class="bg-white ">
        <MultiSelect.content
          id="metrics-multi-select"
          selected_text="Selected metrics"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "metrics", keys: @node_info.selected_metrics_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "metrics", keys: @unselected_metrics_keys}
          ]}
          show_options={@show_metric_options}
        />

        <div class="p-2">
          <div class="grid grid-cols-4 w-3xl gap-2 items-center ">
            <%= for service <- @node_info.selected_services_keys do %>
              <%= for metric <- @node_info.selected_metrics_keys do %>
                <% app = Enum.find(@node_info.node, &(&1.service == service)) %>
                <%= if  metric in app.metrics_keys do %>
                  <% data_key = data_key(service, metric) %>
                  <VmMemory.content
                    title={"#{metric} [#{app.name}]"}
                    service={service}
                    metric={metric}
                    cols={@form.params["num_cols"]}
                    metrics={Map.get(@streams, data_key)}
                  />
                <% end %>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Page
  def handle_mount(socket) do
    # Subscribe to notifications if new metric is received
    Telemetry.subscribe_for_new_keys()

    socket
    |> assign(:node_info, update_node_info())
    |> assign(:node_data, %{})
    |> assign(:metric_config, %{})
    |> assign(form: to_form(default_form_options()))
    |> assign(:show_metric_options, false)
  end

  @impl Page
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Live Metrics")
  end

  @impl Page
  def handle_parent_event(
        "form-update",
        %{"num_cols" => num_cols, "start_time" => start_time},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    start_time_integer = start_time_to_integer(start_time)

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, service_acc ->
        Enum.reduce(node_info.selected_metrics_keys, service_acc, fn metric_key, metric_acc ->
          data_key = data_key(service_key, metric_key)
          dom_id_fun = &"#{data_key}-#{&1.timestamp}"

          metric_acc
          |> stream(data_key, [], reset: true)
          |> stream(
            data_key,
            Telemetry.list_data_by_node_key(service_key, metric_key, from: start_time_integer),
            dom_id: dom_id_fun
          )
          |> assign_metric_config(data_key, %{"transition" => false})
        end)
      end)

    {:noreply,
     assign(socket, form: to_form(%{"num_cols" => num_cols, "start_time" => start_time}))}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_metrics_keys
      )

    socket =
      Enum.reduce(node_info.selected_metrics_keys, socket, fn metric_key, acc ->
        Telemetry.unsubscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-remove-item",
        %{"item" => "metrics", "key" => metric_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys -- [metric_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        Telemetry.unsubscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_metrics_keys
      )

    start_time = start_time_to_integer(form.params["start_time"])

    socket =
      Enum.reduce(node_info.selected_metrics_keys, socket, fn metric_key, acc ->
        Telemetry.subscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)
        dom_id_fun = &"#{data_key}-#{&1.timestamp}"

        acc
        |> stream(
          data_key,
          Telemetry.list_data_by_node_key(service_key, metric_key, from: start_time),
          dom_id: dom_id_fun
        )
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event(
        "multi-select-add-item",
        %{"item" => "metrics", "key" => metric_key},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys ++ [metric_key]
      )

    start_time = start_time_to_integer(form.params["start_time"])

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        Telemetry.subscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)
        dom_id_fun = &"#{data_key}-#{&1.timestamp}"

        acc
        |> stream(
          data_key,
          Telemetry.list_data_by_node_key(service_key, metric_key, from: start_time),
          dom_id: dom_id_fun
        )
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_parent_event("toggle-options", _value, socket) do
    show_metric_options = !socket.assigns.show_metric_options

    {:noreply, socket |> assign(:show_metric_options, show_metric_options)}
  end

  @impl Page
  def handle_info({:metrics_new_data, service, key, data}, socket) do
    data_key = data_key(service, key)

    {:noreply,
     socket
     |> stream_insert(data_key, data)
     |> assign_metric_config(data_key, %{"transition" => true})}
  end

  def handle_info(
        {:metrics_new_keys, _service, _new_keys},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  defp data_key(service, metric), do: "#{service}::#{metric}"

  defp assign_metric_config(
         %{assigns: %{metric_config: metric_config}} = socket,
         data_key,
         attributes
       ) do
    updated_data =
      metric_config
      |> Map.get(data_key, %{})
      |> Map.merge(attributes)

    assign(socket, :metric_config, Map.put(metric_config, data_key, updated_data))
  end

  defp default_form_options, do: %{"num_cols" => "2", "start_time" => "5 minutes"}

  defp start_time_to_integer("1 minute"), do: 1
  defp start_time_to_integer("5 minutes"), do: 5
  defp start_time_to_integer("15 minutes"), do: 15
  defp start_time_to_integer("30 minutes"), do: 30

  defp node_info_new,
    do: %{
      services_keys: [],
      metrics_keys: [],
      selected_services_keys: [],
      selected_metrics_keys: [],
      node: []
    }

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services_keys, selected_metrics_keys) do
    initial_map = %{
      node_info_new()
      | selected_services_keys: selected_services_keys,
        selected_metrics_keys: selected_metrics_keys
    }

    [0]
    |> Enum.reduce(initial_map, fn instance,
                                   %{
                                     services_keys: services_keys,
                                     metrics_keys: metrics_keys,
                                     node: node
                                   } = acc ->
      instance_metrics_keys = Telemetry.get_keys_by_instance(instance)
      service = Telemetry.node_by_instance(instance) |> to_string
      [name, _hostname] = String.split(service, "@")

      metrics_keys = (metrics_keys ++ instance_metrics_keys) |> Enum.sort() |> Enum.uniq()
      services_keys = Enum.sort(services_keys ++ [service])

      node =
        if service in selected_services_keys do
          [
            %{
              name: name,
              metrics_keys: instance_metrics_keys,
              service: service
            }
            | node
          ]
        else
          node
        end

      %{acc | services_keys: services_keys, metrics_keys: metrics_keys, node: node}
    end)
  end
end
