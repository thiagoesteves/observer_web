defmodule ObserverWeb.Telemetry.Producer.PhxLvSocket do
  @moduledoc """
  Telemetry function that collects phoenix liveview socket metrics
  """

  import Telemetry.Metrics

  alias ObserverWeb.Telemetry.Consumer

  @default_lv_get_state_timeout 300

  @type t :: %__MODULE__{
          module: atom(),
          event: list()
        }

  defstruct module: nil,
            event: []

  @cache_key {__MODULE__, :phx_endpoints}

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  def process do
    cached_phx_endpoints = Process.get(@cache_key, [])

    # Check if the cache is populated, if not, verify if there is any
    # Endpoint available
    phx_endpoints =
      if cached_phx_endpoints == [] do
        case fetch_endpoints() do
          [] ->
            []

          endpoints ->
            phx_endpoints = Enum.map(endpoints, &process_endpoint/1)

            Process.put(@cache_key, phx_endpoints)

            phx_endpoints
        end
      else
        cached_phx_endpoints
      end

    Enum.each(phx_endpoints, fn
      %__MODULE__{module: module, event: event} ->
        module
        |> safe_which_children()
        |> Enum.each(fn
          {Phoenix.LiveView.Socket, lv_socket_pid, :supervisor, _data} ->
            supervisors = :supervisor.which_children(lv_socket_pid)
            sockets = fetch_sockets(supervisors)

            :telemetry.execute(
              event,
              %{
                total: sockets |> length(),
                supervisors: supervisors |> length(),
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
  defp process_endpoint(endpoint) do
    [name] =
      endpoint
      |> to_string()
      |> String.split(["Elixir.", ".Endpoint"], trim: true)

    name = name |> String.downcase() |> String.to_atom()

    event = [:phoenix, :liveview, :socket, name]
    metric = (event ++ [:total]) |> Enum.join(".") |> summary()

    :telemetry.attach(
      {__MODULE__, event, self()},
      event,
      &Consumer.handle_event/4,
      {[metric], nil, Node.self()}
    )

    %__MODULE__{module: endpoint, event: event}
  end

  defp sockets_connected(sockets) do
    sockets
    |> Enum.reduce(0, fn socket, acc ->
      case ObserverWeb.Apps.Process.state(socket, @default_lv_get_state_timeout) do
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

  def fetch_endpoints do
    filter_supervisor_endpoints = fn
      {_index, _pid, :supervisor, [name]}, acc when is_atom(name) ->
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
             children when is_list(children) <- safe_which_children(child_pid) do
          Enum.reduce(children, [], &filter_supervisor_endpoints.(&1, &2))
        else
          _ ->
            []
        end

      if endpoint_name != [], do: acc ++ endpoint_name, else: acc
    end)
  end

  # Some application roots are plain GenServers, not supervisors (e.g.
  # `:ex_hash_ring`'s `ExHashRing.Info`). `:supervisor.which_children/1` is just
  # `gen_server:call(pid, :which_children)` under the hood, so it crashes any
  # GenServer that lacks that handle_call clause. We can't rescue the callee
  # from the caller — the crash happens inside the target process before any
  # exit reaches us — so we have to filter callees up-front via the OTP
  # `$initial_call` convention. The trailing catch is belt-and-suspenders for
  # processes that died between the check and the call.
  defp safe_which_children(supervisor) do
    with pid when is_pid(pid) <- whereis(supervisor),
         true <- supervisor?(pid) do
      :supervisor.which_children(pid)
    else
      _ -> []
    end
  catch
    :exit, _ -> []
  end

  defp whereis(pid) when is_pid(pid), do: pid
  defp whereis(name) when is_atom(name), do: Process.whereis(name)
  defp whereis(_), do: nil

  defp supervisor?(pid) when is_pid(pid) do
    match?({:supervisor, _, _}, :proc_lib.initial_call(pid))
  end

  defp supervisor?(_), do: false
end
