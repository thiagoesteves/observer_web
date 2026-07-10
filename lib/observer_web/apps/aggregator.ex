defmodule ObserverWeb.Apps.Aggregator do
  @moduledoc """
  Aggregates an application's supervision tree (as built by `ObserverWeb.Apps.info/2`) into
  per-application totals - the observer_cli App pane's view: how many processes/ports an
  application holds and how much memory, reductions and message-queue backlog they account for.

  Counting walks the already-fetched tree, so it costs no RPCs. Summing process stats does one
  `Rpc.pinfo/2` per process (location transparent, so remote applications work), which is why it
  is a separate, on-demand step - and why it's capped: trees with more processes than the cap
  report a partial sum, flagged as such, instead of hammering the observed node.
  """

  alias ObserverWeb.Apps
  alias ObserverWeb.Rpc

  @pinfo_cap 2_000

  @type counts :: %{
          processes: non_neg_integer(),
          ports: non_neg_integer(),
          references: non_neg_integer()
        }
  @type stats :: %{
          memory: non_neg_integer(),
          reductions: non_neg_integer(),
          message_queue_len: non_neg_integer(),
          sampled: non_neg_integer(),
          partial?: boolean()
        }

  @doc """
  Counts the tree's processes, ports and references. Pure tree walk, no RPCs.
  """
  @spec count(Apps.t() | map()) :: counts()
  def count(tree) do
    tree
    |> collect_ids()
    |> Enum.reduce(%{processes: 0, ports: 0, references: 0}, fn
      id, acc when is_pid(id) -> %{acc | processes: acc.processes + 1}
      id, acc when is_port(id) -> %{acc | ports: acc.ports + 1}
      id, acc when is_reference(id) -> %{acc | references: acc.references + 1}
      _unknown, acc -> acc
    end)
  end

  @doc """
  Sums memory, reductions and message-queue length over the tree's processes (one `Rpc.pinfo/2`
  per process, capped at #{@pinfo_cap} - see the moduledoc). Processes that died since the tree
  was built are skipped.
  """
  @spec stats(Apps.t() | map()) :: stats()
  def stats(tree) do
    pids = tree |> collect_ids() |> Enum.filter(&is_pid/1) |> Enum.uniq()
    {sampled_pids, dropped} = Enum.split(pids, @pinfo_cap)

    initial = %{
      memory: 0,
      reductions: 0,
      message_queue_len: 0,
      sampled: 0,
      partial?: dropped != []
    }

    Enum.reduce(sampled_pids, initial, fn pid, acc ->
      case Rpc.pinfo(pid, [:memory, :reductions, :message_queue_len]) do
        [{:memory, memory}, {:reductions, reductions}, {:message_queue_len, mq}]
        when is_integer(memory) and is_integer(reductions) and is_integer(mq) ->
          %{
            acc
            | memory: acc.memory + memory,
              reductions: acc.reductions + reductions,
              message_queue_len: acc.message_queue_len + mq,
              sampled: acc.sampled + 1
          }

        _dead_or_unexpected ->
          acc
      end
    end)
  end

  defp collect_ids(%{id: id, children: children}) do
    [id | Enum.flat_map(children, &collect_ids/1)]
  end

  # coveralls-ignore-start
  defp collect_ids(_unexpected), do: []
  # coveralls-ignore-stop
end
