defmodule ObserverWeb.Telemetry.Producer.PhxLvSocket do
  @moduledoc """
  Telemetry function that collects phoenix liveview socket metrics
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  def process_phoenix_liveview_sockets do
    cached_endpoints = Process.get(:endpoints, nil)

    endpoints =
      if is_nil(cached_endpoints) do
        endpoints = fetch_endpoints()

        if endpoints != [] do
          Process.put(:endpoints, endpoints)
        end

        endpoints
      else
        cached_endpoints
      end

    Enum.each(endpoints, fn
      endpoint ->
        endpoint
        |> :supervisor.which_children()
        |> Enum.each(fn
          {Phoenix.LiveView.Socket, lv_socket_pid, :supervisor, _data} ->
            supervisors = :supervisor.which_children(lv_socket_pid)
            sockets = fetch_sockets(supervisors)

            :telemetry.execute(
              [:phoenix, :liveview, :socket],
              %{
                supervisors: supervisors |> length(),
                total: sockets |> length(),
                connected: sockets_connected(sockets)
              },
              %{}
            )

          _ ->
            :ok
        end)
    end)
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
