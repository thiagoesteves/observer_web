defmodule ObserverWeb.Processes do
  @moduledoc """
  Samples and ranks the processes of a node, etop-style.

  Sampling delegates to `:observer_backend.etop_collect/1` (part of `runtime_tools`, which
  Observer Web already requires on every node for `:dbg` tracing) - the same collector `etop`
  itself uses against remote nodes, so one RPC round trip returns every process's memory,
  cumulative reductions, message queue length, name and current function, regardless of the
  observer_web version (or absence) on the observed node.

  NOTE: `:observer_backend.etop_collect/1` has a documented side effect: when the
  `:scheduler_wall_time` system flag is off, it turns the flag on and holds it (via a monitor)
  until the collector process - here, the LiveView showing the Processes page - dies. This is
  exactly how running `etop` against a node behaves; the flag adds a small scheduler accounting
  cost and is switched back off when the page is closed.

  Reductions are cumulative counters, so ranking by "load" uses the delta between two
  consecutive samples (`rank/2` with the previous sample's reductions map) - the first sample
  ranks by the cumulative value, exactly like `etop`'s first tick.
  """

  alias ObserverWeb.Rpc

  @rpc_timeout 10_000

  @type process_row :: %{
          pid: pid(),
          name: String.t(),
          memory: non_neg_integer(),
          reductions: non_neg_integer(),
          reductions_diff: non_neg_integer(),
          message_queue_len: non_neg_integer(),
          current_function: String.t()
        }

  @type sample :: %{
          node: node(),
          process_count: non_neg_integer(),
          run_queue: non_neg_integer(),
          memory: %{optional(atom()) => non_neg_integer()},
          processes: [process_row()]
        }

  @doc """
  Collects one sample of every process on `node`.

  The `#etop_info{}`/`#etop_proc_info{}` records are decoded positionally - their shape is part
  of `runtime_tools`' cross-node collector contract and has been stable across OTP releases (the
  GUI observer and `etop` rely on it the same way). Anything unexpected is reported as an error
  instead of crashing the caller.
  """
  @spec sample(node(), timeout()) :: {:ok, sample()} | {:error, term()}
  def sample(node \\ Node.self(), timeout \\ @rpc_timeout) do
    case Rpc.call(node, :observer_backend, :etop_collect, [self()], timeout) do
      :ok ->
        receive_sample(node, timeout)

      {:badrpc, reason} ->
        {:error, reason}

      unexpected ->
        {:error, {:unexpected_reply, unexpected}}
    end
  end

  defp receive_sample(node, timeout) do
    receive do
      {_collector_pid,
       {:etop_info, _now, process_count, _wall_clock, _runtime, run_queue, _alloc_areas, memi,
        procinfo}} ->
        {:ok,
         %{
           node: node,
           process_count: process_count,
           run_queue: run_queue,
           memory: Map.new(memi),
           processes: Enum.map(procinfo, &decode_proc_info/1)
         }}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp decode_proc_info({:etop_proc_info, pid, mem, reds, name, _runtime, cf, mq}) do
    %{
      pid: pid,
      name: format_name(name),
      memory: mem,
      reductions: reds,
      reductions_diff: reds,
      message_queue_len: mq,
      current_function: format_mfa(cf)
    }
  end

  # etop_collect reports the registered name (atom), the `:"$process_label"` (binary) or the
  # initial call ({m, f, a}) - whichever it finds first.
  defp format_name(name) when is_atom(name), do: inspect(name)
  defp format_name(name) when is_binary(name), do: name
  defp format_name({_m, _f, _a} = mfa), do: format_mfa(mfa)
  defp format_name(other), do: inspect(other)

  defp format_mfa({mod, fun, arity}), do: "#{inspect(mod)}.#{fun}/#{arity}"
  defp format_mfa(other), do: inspect(other)

  @doc """
  Ranks a sample's processes by `sort_by`, keeping the top `limit` rows.

  `previous_reductions` is a `%{pid => cumulative_reductions}` map from the preceding sample;
  each row's `reductions_diff` becomes the delta since then (processes not present before - or
  on the very first sample - keep their cumulative count, like `etop`'s first tick).
  """
  @spec rank(sample(), :reductions | :memory | :message_queue_len, pos_integer(), map()) ::
          [process_row()]
  def rank(%{processes: processes}, sort_by, limit, previous_reductions \\ %{}) do
    sort_key =
      case sort_by do
        :reductions -> :reductions_diff
        other -> other
      end

    processes
    |> Enum.map(fn %{pid: pid, reductions: reds} = row ->
      %{row | reductions_diff: reds - Map.get(previous_reductions, pid, 0)}
    end)
    |> Enum.sort_by(&Map.fetch!(&1, sort_key), :desc)
    |> Enum.take(limit)
  end

  @doc """
  Extracts the `%{pid => cumulative_reductions}` map used as `previous_reductions` for the next
  `rank/4` call.
  """
  @spec reductions_by_pid(sample()) :: %{optional(pid()) => non_neg_integer()}
  def reductions_by_pid(%{processes: processes}) do
    Map.new(processes, fn %{pid: pid, reductions: reds} -> {pid, reds} end)
  end

  @doc """
  Fetches display-ready details for one process, used by the Processes page drill-down panel.
  Returns `{:error, :not_found}` when the process has already died.
  """
  @spec details(pid()) :: {:ok, [{String.t(), String.t()}]} | {:error, :not_found}
  def details(pid) do
    keys = [
      :registered_name,
      :status,
      :memory,
      :total_heap_size,
      :heap_size,
      :stack_size,
      :message_queue_len,
      :reductions,
      :current_stacktrace,
      :initial_call,
      :trap_exit,
      :links,
      :monitors,
      :monitored_by,
      :group_leader
    ]

    case Rpc.pinfo(pid, keys) do
      info when is_list(info) ->
        {:ok, Enum.map(info, fn {key, value} -> {format_key(key), format_value(key, value)} end)}

      _dead ->
        {:error, :not_found}
    end
  end

  defp format_key(key), do: key |> to_string() |> String.replace("_", " ")

  defp format_value(:current_stacktrace, stacktrace) when is_list(stacktrace) do
    Enum.map_join(stacktrace, "\n", fn {mod, fun, arity, _location} ->
      format_mfa({mod, fun, arity})
    end)
  end

  defp format_value(:initial_call, {_m, _f, _a} = mfa), do: format_mfa(mfa)

  defp format_value(_key, value), do: inspect(value, limit: 25, printable_limit: 256)
end
