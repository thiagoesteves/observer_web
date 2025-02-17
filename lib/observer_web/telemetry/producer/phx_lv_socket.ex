defmodule ObserverWeb.Telemetry.Producer.PhxLvSocket do
  @moduledoc """
  GenServer that collects phoenix metrics and produce its statistics
  """
  use GenServer

  @phoenix_interval :timer.seconds(5)

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    phoenix_interval = Keyword.get(args, :phoenix_interval, @phoenix_interval)

    # NOTE: Fetching the current endpoint modules must be delayed to ensure
    #       that all modules are fully loaded by the Erlang system.
    Process.send_after(self(), :capture_endpoints, phoenix_interval)

    {:ok, %{endpoints: nil, phoenix_interval: phoenix_interval}}
  end

  @impl true
  def handle_info(:capture_endpoints, %{phoenix_interval: phoenix_interval} = state) do
    case fetch_endpoints() do
      [] ->
        Process.send_after(self(), :capture_endpoints, phoenix_interval)
        {:noreply, state}

      endpoints ->
        Process.send_after(self(), :collect_phoenix_metrics, phoenix_interval)
        {:noreply, %{state | endpoints: endpoints}}
    end
  end

  def handle_info(
        :collect_phoenix_metrics,
        %{endpoints: endpoints, phoenix_interval: phoenix_interval} = state
      ) do
    endpoints
    |> Enum.each(fn endpoint ->
      endpoint
      |> :supervisor.which_children()
      |> Enum.each(fn
        {Phoenix.LiveView.Socket, lv_socket_pid, :supervisor, _data} ->
          supervisors = :supervisor.which_children(lv_socket_pid)
          sockets = fetch_sockets(supervisors)

          measurements = %{
            supervisors_total: supervisors |> length(),
            sockets_total: sockets |> length(),
            sockets_connected: sockets_connected(sockets)
          }

          [
            %{
              metrics: [
                %{
                  name: "phoenix.liveview.socket.total",
                  value: measurements.sockets_total,
                  unit: "",
                  info: "",
                  tags: %{},
                  type: "summary"
                }
              ],
              reporter: Node.self(),
              measurements: measurements
            }
          ]
          |> Enum.each(&ObserverWeb.Telemetry.push_data(&1))

        _ ->
          nil
      end)
    end)

    Process.send_after(self(), :collect_phoenix_metrics, phoenix_interval)

    {:noreply, state}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp sockets_connected(sockets) do
    sockets
    |> Enum.reduce(0, fn socket, acc ->
      case ObserverWeb.Apps.Process.state(socket) do
        {:ok, %{socket: %Phoenix.LiveView.Socket{transport_pid: transport_pid}}}
        when is_pid(transport_pid) ->
          acc + 1

        _ ->
          acc
      end
    end)
  end

  defp fetch_sockets(supervisors) do
    supervisors
    |> Enum.reduce([], fn {_index, sup_pid, :supervisor, _meta}, acc ->
      sockets =
        sup_pid
        |> :supervisor.which_children()
        |> Enum.map(fn {_, socket_pid, :worker, _} -> socket_pid end)

      acc ++ sockets
    end)
  end

  defp fetch_endpoints do
    filter_supervisor_endpoints = fn
      {name, _pid, :supervisor, [_name]}, acc ->
        if String.contains?(name |> to_string, ".Endpoint") do
          acc ++ [name]
        else
          acc
        end

      _, acc ->
        acc
    end

    ObserverWeb.Apps.list()
    |> Enum.map(& &1.name)
    |> Enum.reduce([], fn app, acc ->
      endpoint_name =
        with pid <- :application_controller.get_master(app),
             {child_pid, _application_name} <- :application_master.get_child(pid),
             children when is_list(children) <- :supervisor.which_children(child_pid) do
          Enum.reduce(children, [], &filter_supervisor_endpoints.(&1, &2))
        else
          _ ->
            []
        end

      if endpoint_name != [], do: acc ++ endpoint_name, else: acc
    end)
  end
end
