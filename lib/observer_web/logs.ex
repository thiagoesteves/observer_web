defmodule ObserverWeb.Logs do
  @moduledoc """
  Bounded, read-only access to the log files of a node - the web equivalent of observer_cli's
  log tail pane: read the last chunk of a logger file during an incident without flushing or
  locking anything.

  Log sources are restricted to the file-backed `:logger` handlers configured on the target
  node (`:logger.get_handler_config/0`); free-form paths are never accepted from the caller, so
  the dashboard cannot be used to read arbitrary files.

  The tail itself is a single stdlib-only RPC: a pre-parsed `:erl_eval` expression opens the
  file on the remote node, `pread`s at most `max_bytes` from the end and closes it. Nothing is
  required on the target node beyond OTP itself, matching how `ObserverWeb.SystemInfo` keeps
  remote calls version-independent.

  ## Making logs visible

  Elixir applications log to the console by default, in which case there is nothing to tail.
  Add a file handler to the observed application (standard Elixir 1.15+ configuration):

  ```elixir
  # config/config.exs
  config :my_app, :logger, [
    {:handler, :file_log, :logger_std_h,
     %{config: %{file: ~c"/var/log/my_app/my_app.log"}, formatter: Logger.Formatter.new()}}
  ]

  # lib/my_app/application.ex - in start/2
  Logger.add_handlers(:my_app)
  ```

  Or attach one at runtime without restarting:

  ```elixir
  :logger.add_handler(:file_log, :logger_std_h, %{config: %{file: ~c"/var/log/my_app.log"}})
  ```

  See the installation guide's "Logs" section for rotation options and Erlang release notes.
  """

  alias ObserverWeb.Rpc

  @rpc_timeout 5_000

  @default_max_bytes 64 * 1_024
  @max_bytes_limit 1_024 * 1_024

  @type handler :: %{id: atom(), module: module(), file: String.t()}
  @type tail :: %{content: String.t(), size: non_neg_integer(), truncated?: boolean()}

  # Evaluated on the remote node via :erl_eval with Path/MaxBytes bindings: bounded pread of
  # the file's last chunk. Raw mode keeps the descriptor inside the rpc process, so nothing
  # leaks if the call is interrupted.
  @tail_source ~c"""
  case file:open(Path, [read, raw, binary]) of
      {ok, Fd} ->
          {ok, Size} = file:position(Fd, eof),
          Offset = erlang:max(Size - MaxBytes, 0),
          Result =
              case Size of
                  0 ->
                      {ok, <<>>, 0};
                  _ ->
                      case file:pread(Fd, Offset, erlang:min(MaxBytes, Size)) of
                          {ok, Data} -> {ok, Data, Size};
                          eof -> {ok, <<>>, Size};
                          Error -> Error
                      end
              end,
          file:close(Fd),
          Result;
      Error ->
          Error
  end.
  """

  @doc """
  File-backed `:logger` handlers configured on the node.

  Handlers without a file (e.g. console/standard_io) are skipped, as is anything with an
  unexpected config shape.
  """
  @spec list_handlers(node()) :: [handler()]
  def list_handlers(node) do
    case Rpc.call(node, :logger, :get_handler_config, [], @rpc_timeout) do
      handlers when is_list(handlers) ->
        Enum.flat_map(handlers, fn
          %{id: id, module: module, config: %{file: file}}
          when is_list(file) or is_binary(file) ->
            [%{id: id, module: module, file: to_string(file)}]

          _handler_without_file ->
            []
        end)

      _unavailable ->
        []
    end
  end

  @doc """
  Read at most `max_bytes` (capped at #{@max_bytes_limit} bytes) from the end of `file` on
  `node`. The file must belong to one of the node's logger handlers - see `list_handlers/1`.

  When the file is larger than the requested chunk, the (usually partial) first line is dropped
  and `truncated?` is set.
  """
  @spec tail(node(), String.t(), pos_integer()) :: {:ok, tail()} | {:error, term()}
  def tail(node, file, max_bytes \\ @default_max_bytes) do
    max_bytes = max_bytes |> min(@max_bytes_limit) |> max(1)
    allowed_files = node |> list_handlers() |> Enum.map(& &1.file)

    if file in allowed_files do
      bounded_read(node, file, max_bytes)
    else
      {:error, :not_a_logger_file}
    end
  end

  defp bounded_read(node, file, max_bytes) do
    bindings =
      :erl_eval.new_bindings()
      |> then(&:erl_eval.add_binding(:Path, file, &1))
      |> then(&:erl_eval.add_binding(:MaxBytes, max_bytes, &1))

    case Rpc.call(node, :erl_eval, :exprs, [tail_exprs(), bindings], @rpc_timeout) do
      {:value, {:ok, data, size}, _bindings} ->
        truncated? = size > max_bytes

        {:ok, %{content: normalize_chunk(data, truncated?), size: size, truncated?: truncated?}}

      {:value, {:error, reason}, _bindings} ->
        {:error, reason}

      error ->
        {:error, error}
    end
  end

  defp tail_exprs do
    {:ok, tokens, _end} = :erl_scan.string(@tail_source)
    {:ok, exprs} = :erl_parse.parse_exprs(tokens)

    exprs
  end

  # A truncated chunk almost always starts mid-line; drop everything up to the first newline so
  # the pane only shows complete lines.
  defp normalize_chunk(data, true = _truncated?) do
    case :binary.split(data, "\n") do
      [_partial, rest] -> rest
      [only] -> only
    end
  end

  defp normalize_chunk(data, false = _truncated?), do: data
end
