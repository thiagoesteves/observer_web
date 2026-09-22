defmodule ObserverWeb.ProcessLabel do
  @moduledoc """
  Resolves human-readable names for processes, using the same fallback chain `etop` uses.

  The steps, in order of preference:

    1. the registered name, when the process has one;
    2. the `Process.set_label/1` process label, stored by OTP in the `:"$process_label"`
       dictionary entry;
    3. the `proc_lib` initial call (how GenServers, Supervisors and Tasks identify themselves),
       suffixed with the pid to keep concurrent instances of the same module apart;
    4. the inspected pid.

  Callers pick how far down the chain they want to go. `resolve/1` walks all of it and always
  returns something printable; the `from_*` functions are pure and operate on data the caller has
  already fetched, so a page that pulls `:dictionary` for other reasons pays no extra round trip.

  Labels matter most for processes that have no registered name - LiveViews, `Registry`/`:via`
  registrations, connection-pool workers and `Task`s - which is precisely the population that
  would otherwise render as a bare pid.
  """

  alias ObserverWeb.Rpc

  @doc """
  Full fallback chain for `pid`, always returning a printable string.

  Works for local and remote pids (`ObserverWeb.Rpc.pinfo/2` is location transparent). Falls back
  to the inspected pid when the process has already died by the time it is asked - common for
  short-lived processes.
  """
  @spec resolve(pid()) :: String.t()
  def resolve(pid) do
    # The whole dictionary is fetched instead of the leaner `{:dictionary, :"$process_label"}`
    # item form because the latter requires OTP 26.2+ on the *observed* node.
    case Rpc.pinfo(pid, [:registered_name, :dictionary, :initial_call]) do
      [{:registered_name, name}, {:dictionary, dictionary}, {:initial_call, initial_call}] ->
        from_registered_name(name) || from_dictionary(dictionary) ||
          from_initial_call(dictionary, initial_call, pid) || inspect(pid)

      _dead ->
        inspect(pid)
    end
  end

  @doc """
  The registered name as a string, or `nil` when the process has none.

  An alive-but-unregistered process reports `[]` as its registered name.
  """
  @spec from_registered_name(term()) :: String.t() | nil
  def from_registered_name(name) when is_atom(name) and name != nil, do: inspect(name)
  def from_registered_name(_unregistered), do: nil

  @doc """
  The `Process.set_label/1` label held in an already-fetched process dictionary, or `nil`.

  Labels are arbitrary terms, so anything that is not already a binary is inspected.
  """
  @spec from_dictionary(term()) :: String.t() | nil
  def from_dictionary(dictionary) when is_list(dictionary) do
    case List.keyfind(dictionary, :"$process_label", 0) do
      {_key, label} when is_binary(label) -> label
      {_key, label} -> inspect(label)
      nil -> nil
    end
  end

  def from_dictionary(_no_dictionary), do: nil

  @doc """
  The `proc_lib` initial call, suffixed with the pid, or `nil` when there is nothing useful.

  proc_lib-spawned processes carry their real starting MFA in the `:"$initial_call"` dictionary
  entry; the raw `:initial_call` for them is the meaningless proc_lib/erlang wrapper. Anything
  without the dictionary entry that only reports a generic spawn wrapper returns `nil`.
  """
  @spec from_initial_call(term(), term(), pid()) :: String.t() | nil
  def from_initial_call(dictionary, initial_call, pid) do
    initial_call =
      case is_list(dictionary) && List.keyfind(dictionary, :"$initial_call", 0) do
        {_key, {_m, _f, _a} = mfa} -> mfa
        _no_entry -> initial_call
      end

    case initial_call do
      {mod, _f, _a} when mod in [:erlang, :proc_lib] -> nil
      {mod, fun, arity} -> "#{inspect(mod)}.#{fun}/#{arity} #{inspect(pid)}"
      _unknown -> nil
    end
  end
end
